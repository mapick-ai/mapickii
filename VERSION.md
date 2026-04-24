# Changelog

All notable changes to Mapickii will be documented in this file.

## v0.0.12 - 2026-04-24

### Changed

- **Hardcode API base URL**: `shell.js` and `shell.sh` no longer honor the
  `MAPICKII_API_BASE` environment variable. The base is pinned to
  `https://api.mapick.ai/api/v1`. `SKILL.md` no longer advertises
  `primaryEnv`, and the `--help` output drops the env-var line.

## v0.0.11 - 2026-04-24

### Fixed

- **Restore `/api/v1` prefix in default `API_BASE`**: v0.0.10 removed the
  prefix from both `shell.js` and `shell.sh`, causing every remote call
  to return 404 because the backend sets `setGlobalPrefix("api/v1")` in
  `main.ts`. All 20 endpoints (search, recommend, bundle, assistant,
  users, events, report, share, security) are now reachable again.
  - `shell.js`: `MAPICKII_API_BASE` default → `https://api.mapick.ai/api/v1`
  - `shell.sh`: `MAPICKII_API_BASE` default → `https://api.mapick.ai/api/v1`

### Notes

- Users who explicitly set `MAPICKII_API_BASE=https://api.mapick.ai`
  (without a prefix) must update it to include `/api/v1`, or unset it so
  the new default applies.
- Clear stale 404 recommend cache after upgrade: `rm -rf ~/.mapickii/cache`.

## v0.0.4 - 2026-04-24

### Fixed

- **API 端点路径修复**：修复 mapickii 调用后端 API 时多处路径不匹配的问题
  - `GET /assistant/workflow?userId={fp}` → `GET /assistant/workflow/{fp}`
  - `GET /assistant/daily?userId={fp}` → `GET /assistant/daily-digest/{fp}`
  - `GET /assistant/weekly?userId={fp}` → `GET /assistant/weekly/{fp}`
  - `GET /bundle/recommend` → `GET /bundle/recommend/list`
  - `POST /bundle/track` → `POST /bundle/seed`
  - `POST /user/trusted-skills` → `POST /users/trusted-skills`
  - `DELETE /user/data` → `DELETE /users/data`
  - `POST /user/consent` → `POST /users/consent`

## v0.0.3 - 2026-04-24

First V1-reset capable release — merges the long-running `1.0/dev` line
into `main`, bringing the privacy layer, bundle two-step install, the v2
recommendation feed, persona + share, security scoring and the first-run
summary card to users installing from `main` or tag.

### Added

- **First-run summary + workflow profile (PR-16)**: the first time a
  user talks to the agent after install, Mapickii emits a one-shot
  summary card (privacy / skill counts / zombies / top-used / security
  grades) and asks one workflow question. The answer seeds
  `user_profile_tags`, which the backend uses as a 15 % per-match boost
  on recommend feed results. Completely one-time — after the first run
  it never fires again. Manual `/mapickii profile clear` replays it.
- **New shell commands**: `summary`, `first-run-done`, `profile set|get|clear`,
  `recommend --with-profile`.
- **Recommendation & search commands** (`/mapickii recommend`,
  `/mapickii search`) + backend v2 contract (PR-4 / PR-8).
- **Privacy layer** (`/mapickii privacy status|delete-all|trust|untrust|consent-agree|consent-decline`)
  with `redact.py` + code-block whitelist + false-positive heuristics
  (PR-5 / PR-13).
- **Persona report & share** (`/mapickii report`, `/mapickii share`) with
  localised production prompt (PR-12).
- **Security score & reporting** (`/mapickii security <skillId>`,
  `security:report`) with Grade A/B/C surfaces and alternatives (PR-10 / PR-12).
- **Bundle two-step install** with scan event reporting to keep the
  backend skill_records table in sync (PR-2).
- **kill_switch consumer**: every command gates on `/system/status`
  with a 5-minute local cache; maintenance mode short-circuits to a
  localised message (PR-13).

### Changed

- SKILL.md reorganised: Runtime Detection, Red Flags, Intent Routing
  and Lifecycle Model sections now ship alongside the new First-run
  summary section.
- CONFIG.md gains `first_run_complete`, `first_run_at`, `user_profile`,
  `user_profile_tags`, `user_profile_set_at`.

### Backend (mapick-api) companion

- `POST /users/:userId/profile-text` (DeviceFpGuard, 5/day).
- `GET /recommend/feed?profileTags=<csv>` — non-destructive 15 % boost.
- users table gains `profile_text` / `profile_tags` / `profile_set_at`.

## v0.0.2 - 2026-04-23

### Fixed

- `install.sh` now downloads the tarball to a file before extracting, with `curl --retry 3 --retry-delay 2`. Previously the streamed `curl | tar` pipeline could leave a truncated archive on transient network drops, causing spurious "Failed to download" errors.

## v0.0.1 - 2026-04-23

First public release of Mapickii — the Mapick ecosystem butler.

### Supported platform

- OpenClaw (`~/.openclaw/skills/mapickii/`)
