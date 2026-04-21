---
name: mapickii
description: Mapickii — Skill recommendation & privacy protection for OpenClaw. Scans your local skills, suggests what you're missing, and keeps other skills from seeing your secrets.
---

# Mapickii

V1 principle: **Recommend to users, protect their privacy, let personas spread.**
Priority: recommendation = privacy > persona sharing > safety score > cleanup > everything else.

All command output below is **English reference** — AI must render in the user's
conversation language.

---

## 1. Recommendation & Discovery

**Why this is first**: Mapickii's core value is helping users find skills they
don't have but should. Everything else is secondary.

### Intent: recommend

Reference triggers (English): recommend, suggest, find skill, what should I
install, best skills, what am I missing, any suggestions, discover, skills for
me, good skills.

**Match in ANY language** — recognize equivalents in whatever language the user
speaks. Only treat this as the `recommend` intent when the user asks about
**skills / tools / what to install** (not general-purpose "recommend a book").

Shell command: `bash shell.sh recommend [limit]`
Backend: `GET /recommend/feed?limit=5` (DeviceFp guarded, 60/h rate limit)

### Intent: search

Reference triggers (English): search, find, look for, is there a skill for,
find a skill that, anything for X.

**Match in ANY language**.

Shell command: `bash shell.sh search <keyword> [limit]`
Backend: `GET /skill/live-search?query=&limit=10` (DeviceFp guarded, 30/min)

### Rendering (recommend)

When shell returns `{ intent: "recommend", items: [...] }`:

1. **Filter out items with `score < 0.4`** — they're too weak to surface.
2. **Open with one sentence**: "I found N skills that might help you."
3. **Show 3 items max**. For each item:
   - Skill name
   - One-line description (translate from `reasonEn` to the user's language)
   - Human-friendly install count ("23K installs")
   - Confidence phrase derived from `score`:
     - `score > 0.7` → "highly recommended" (localized)
     - `0.4 ≤ score ≤ 0.7` → "might be useful" (localized)
   - Safety badge: 🟢 A / 🟡 B / 🔴 C from `safetyGrade`. If `C`, mention the
     top entry from `alternatives[]`.
4. **Close** with a call-to-action: "Reply with 1-3 to install, or ask for more."

**Never** show raw `score` numbers (0.85, 0.62, etc.) to the user — they're
meaningless. Always translate to the confidence phrase above.

### Rendering (search)

When shell returns `{ intent: "search", items: [...] }`:

**If `items` is empty** (empty array or `emptyReason: "no_matches"`), render
this template (translate to user's language):

```
I couldn't find any skills matching "<query>". Try:

- A broader keyword — "git" instead of "github-ops-advanced"
- A category — "testing" / "deployment" / "analytics"
- Or let me recommend based on what you already have: /mapickii recommend

Got a skill name in mind but spelled differently? Tell me and I'll search again.
```

**Otherwise** render like `recommend` above (same score filter, same confidence
phrases, same safety badges, 3-5 items max).

### User says "install it" / "yes" / "1"

After rendering a recommend/search result, wait for the user's reply. On reply:

1. Identify the target item from the last rendered list (by number, name, or
   natural-language reference).
2. From the item's `installCommands[]`, pick the entry where `platform` is
   `openclaw` and run that `command` in the user's shell.
3. On success, call `bash shell.sh recommend:track <recId> <skillId> installed`
   so the backend can tune future recommendations.
4. On failure, reply with the error (translated), and suggest retry or skip.
5. Confirm to user: "✅ {skillName} installed. Want to see more?"

### Caching

Shell caches the last `recommend` response for 24h via `_save_recommendations`.
If the user asks for recommendations again within 24h, shell serves the cached
list (no rate-limit burn). Force refresh: pass an explicit limit argument
(e.g. `recommend 10`) which goes through the full backend call.

---

## 2. Privacy Protection

**Status: placeholder in this PR. The `/mapickii privacy` command group and
redaction engine land in PR-5.**

When a user asks about what data is tracked, how to delete their data, or
privacy concerns, this is the chapter. Until PR-5 ships, point to the
`privacy` note in the first-install JSON: "Anonymous by design. No
registration. No code or conversation content leaves the device."

---

## 3. Persona Report (V1.5)

Not in V1 scope. Leave a one-line mention only.

---

## 4. Status Overview

### Intent: status

Reference triggers (English): status, overview, dashboard, my skills, skill
stats, how am I doing, skill summary.

**Match in ANY language** — recognize equivalents in whatever language the
user speaks. The English words above are reference only, not an exhaustive
allow-list.

Shell command: `bash shell.sh status`
Backend: `GET /assistant/status/:userId` (FpOrApiKeyGuard, DeviceFp accepted)

### Rendering (status)

When shell returns `{ intent: "status", ... }`:

- Lead with a one-sentence health summary: total skills / active / zombie /
  never-used, and the activation rate as a percentage.
- If there's a top workflow, mention it in one line.
- If zombies > 0, gently suggest running `clean`.

Render in the user's language. Keep it tight — no ASCII dividers, no
decorative emojis. Safety-grade emojis (🟢 A / 🟡 B / 🔴 C) are OK when they
carry meaning.

### First install rendering (`status: "first_install"`)

Shell returns a lean JSON:

```json
{
  "status": "first_install",
  "data": {
    "deviceFingerprint": "...",
    "skillsCount": 3,
    "skillNames": ["tasa", "mapick", "stage"]
  },
  "privacy": "Anonymous by design. No registration. ..."
}
```

**Render in the user's conversation language** (English reference below):

1. Greet warmly, in one sentence. Example: "Mapickii is ready."
2. Say it scanned the environment and found `skillsCount` skills. If
   `skillsCount > 0`, list up to 5 from `skillNames`. If `0`, say the canvas
   is empty and Mapickii can help discover skills.
3. Mention one next step. Example: "Ask me anything naturally, or try
   `/mapickii recommend` to see what might help you."
4. Include the one-line `privacy` note verbatim (translate literally — its
   substance matters: anonymous, no registration).

**Do not** render any ASCII logo, prompt for registration, or call a follow-up
command automatically.

---

## 5. Bundle Recommendations (M3)

Bundles solve the single-skill-recommend limit: users often need a cluster of
skills to complete a workflow.

### Intent: bundle

Reference triggers (English): bundle, bundle recommendation, recommend a
bundle, workflow pack, skill pack.

**Match in ANY language**.

| User input                      | Shell command                     | Notes                                  |
| ------------------------------- | --------------------------------- | -------------------------------------- |
| `/mapickii bundle`              | `bundle`                          | List bundles                           |
| `/mapickii bundle <id>`         | `bundle <id>`                     | Bundle detail                          |
| `/mapickii bundle recommend`    | `bundle:recommend`                | Recommend bundles based on installs    |
| `/mapickii bundle install <id>` | `bundle:install <id>`             | Fetch install commands (two-step flow) |
| (internal)                      | `bundle:track-installed <id>`     | AI calls after executing commands      |

### Bundle install — two-step flow (V1, by design)

**Step 1**: `bash shell.sh bundle:install <bundleId>` returns:

```json
{
  "intent": "bundle:install",
  "bundleId": "fullstack-dev",
  "installCommands": [
    { "skillId": "github-ops",     "command": "clawhub install github-ops" },
    { "skillId": "docker-compose", "command": "clawhub install docker-compose" }
  ],
  "installed": false
}
```

**Step 2**: AI executes each `installCommands[i].command` in the user's shell,
tracks per-command result, then calls `bash shell.sh bundle:track-installed <bundleId>`.

**Step 3**: Report summary to the user in their language: "Installed N of M
skills from bundle <name>."

### Failure handling (AI must follow this playbook)

| Failure                      | What to do                                                                                   |
| ---------------------------- | -------------------------------------------------------------------------------------------- |
| `clawhub: command not found` | Stop; tell user OpenClaw CLI is missing (https://openclaw.io); ask whether to retry          |
| Network timeout / DNS fail   | Skip current command, continue with next; summarize failures at end with retry hint          |
| Permission denied            | Report directory; suggest `sudo` or writable path; don't auto-sudo                           |
| "already installed" (exit 0) | Count as success                                                                             |
| Unknown error                | Report first 200 chars of stderr; continue with remaining commands                           |

If **all** commands fail and nothing installs, **do not** call
`bundle:track-installed`.

Rendering: use skill names + short per-item status (✅ installed / ⚠️ failed
with short reason). Render in the user's language.

---

## 6. Security Score (V1 placeholder)

The `/mapickii security <skillId>` command lands in a later PR. Until then,
don't invent safety grades — only show them if they appear in a backend
response.

---

## 7. Zombie Cleanup

### Intent: clean

Reference triggers (English): clean, cleanup, zombies, dead skills, unused,
prune, get rid of unused skills.

**Match in ANY language**.

Shell command: `bash shell.sh clean`
Backend: `GET /user/:userId/zombies` via `clean` case

### Rendering (clean)

When shell returns a zombie list:

- Open with one line: "Found N zombie skills (30+ days inactive)."
- List them as numbered items, short description each.
- Close with a call-to-action: "Reply with numbers to uninstall (e.g. `1 3 5`),
  `all`, or `skip`."

When user replies:
- Numbers (e.g. `1 2`) → look up skillIds from the last rendered list, call
  `bash shell.sh clean:track <skillId>` for each, then `bash shell.sh uninstall <skillId> --confirm`.
- `all` → apply to every zombie.
- `skip` → end the flow; reply "ok".

**Do not** ask the user for a reason. Reason is always `zombie_cleanup`
(handled server-side).

### Intent: uninstall

Reference triggers (English): uninstall, remove skill, delete skill, drop it.

Shell command: `bash shell.sh uninstall <skillId> --confirm`

V1 default: `--scope` is `both` (user-level + project-level). Advanced users
can pass `--scope user` or `--scope project` to limit removal.

**Do not** ask the user which scope to use. The default covers the common case.

---

## 8. Workflow / Daily / Weekly

### Intent: workflow
Reference triggers (English): workflow, routine, pipeline, skill chain, common combos.
**Match in ANY language**.
Shell command: `bash shell.sh workflow`

### Intent: daily
Reference triggers (English): daily, today, yesterday, daily report, what's today.
**Match in ANY language**.
Shell command: `bash shell.sh daily`

### Intent: weekly
Reference triggers (English): weekly, this week, weekly summary, last week.
**Match in ANY language**.
Shell command: `bash shell.sh weekly`

### Rendering for these three

Each returns structured data (recent invocations, trends, top skills). Render
in the user's language, keep to 3-5 bullets max. No decorative emojis or
dividers.

---

## Lifecycle model (reference)

Install → First use → Active → Declining → Zombie → Uninstall

| Stage              | Trigger                          | Behavior                            |
| ------------------ | -------------------------------- | ----------------------------------- |
| Install            | Skill directory exists           | Record install time and path        |
| First use          | First invocation                 | Measure activation delay            |
| Activation timeout | No call within 7 days of install | Flag `activation_timeout`           |
| Active             | ≥ 2 calls in 7 days              | Compute frequency, detect sequences |
| Declining          | This week < 50% of last week     | Internal flag                       |
| Zombie             | No call in 30 days               | Flag `zombie`, surface in `clean`   |
| Uninstall          | User-triggered                   | Record reason, back up to `trash/`  |

---

## Auto-trigger (on every new conversation)

Shell auto-runs `bash shell.sh init` when AI detects a new Mapickii session.
Shell is idempotent: 30-minute cooldown prevents repeated full scans.

Responses:
- `status: "first_install"` → render per chapter 4.
- `status: "rescanned"`, `changed: true` → briefly mention what changed (added
  / removed skills).
- `status: "rescanned"`, `changed: false` or `status: "skip"` → silent.

---

## Command reference

Primary commands (what to suggest to the user):

| Command                  | Purpose                                    |
| ------------------------ | ------------------------------------------ |
| `/mapickii`              | Status overview (alias for `status`)       |
| `/mapickii status`       | Detailed skill status                      |
| `/mapickii scan`         | Force re-scan                              |
| `/mapickii clean`        | List zombies, pick which to remove         |
| `/mapickii workflow`     | Frequent sequences                         |
| `/mapickii daily`        | Daily digest                               |
| `/mapickii weekly`       | Weekly summary                             |
| `/mapickii bundle`       | Browse bundles / install bundle            |

PR-4 will add: `/mapickii recommend`, `/mapickii search <keyword>`.
PR-5 will add: `/mapickii privacy (status / delete-all / trust / consent-*)`.

Internal commands (invoked by AI, not typed by user):
- `bash shell.sh clean:track <skillId>` — record uninstall event
- `bash shell.sh bundle:track-installed <bundleId>` — record bundle install

Debug only:
- `bash shell.sh id` — show local device fingerprint

---

## Execution

Shell expects to run as a subprocess from within the AI conversation. All
responses are single-line JSON. AI should:

1. Parse the JSON (use `json.loads` / `JSON.parse`).
2. Render in the user's language using the chapter guidance above.
3. Never dump raw JSON to the user (except when the user explicitly asks for
   it in debug mode).

Errors: shell responds with `{ "error": "...", "message": "..." }`. AI should
paraphrase the error reason in the user's language, not show the JSON.

---

## CONFIG.md structure (auto-generated)

```yaml
device_fp: <16-hex>            # sha256(hostname|uname-s|uname-m|HOME)[:16]
created_at: <ISO8601>
last_init_at: <ISO8601>        # 30-min idempotency tracker
scan:                          # latest scan result
  scanned_at: <ISO8601>
  skills:
    - id: <skillId>
      name: <displayName>
      path: <absolute-path>
      installed_at: <ISO8601>
      enabled: <bool>
      last_modified: <ISO8601>
  system: { os, arch, hostname, home, editors: {...} }
recommendations:               # cached backend feed (PR-4)
  cached_at: <ISO8601>
  ttl_hours: 24
  items: [...]
```

Do not write to CONFIG.md directly — always go through shell commands.

---

## Error handling

Common error codes from shell:

- `missing_argument` — user didn't supply a required argument; re-prompt
- `protected_skill` — tried to uninstall mapickii / mapick / tasa; refuse gracefully
- `service_unreachable` — backend down or network fail; suggest retry later
- `unknown_command` — typo or unsupported command; suggest `/mapickii help`

Render error reason in the user's language. Don't echo the JSON verbatim.
