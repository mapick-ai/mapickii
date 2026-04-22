# API & Command Reference

## Primary Commands

| Command | Shell | Backend | Rate Limit |
|---------|-------|---------|------------|
| status | `init` / `status` | `GET /assistant/status/:userId` | - |
| recommend | `recommend [limit]` | `GET /recommend/feed` (v2: x-device-fp) | 60/h |
| search | `search <keyword>` | `GET /skills/live-search` | 30/min |
| privacy | `privacy status/trust/delete` | Local + GDPR | - |
| report | `report` | Persona endpoint | 10/day |
| security | `security <skillId>` | Security endpoint | 60/h |
| clean | `clean` | `GET /users/:userId/zombies` | - |
| bundle | `bundle [install]` | Bundle endpoints | - |
| workflow | `workflow` | Workflow endpoint | - |
| daily | `daily` | Daily endpoint | - |
| weekly | `weekly` | Weekly endpoint | - |

## Internal Commands

- `clean:track <skillId>` — record uninstall
- `bundle:track-installed <bundleId>` — record bundle install
- `recommend:track <recId> <skillId> <action>` — tune recommendations