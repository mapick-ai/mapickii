# API & Command Reference

## Primary Commands (User-facing)

| Command | Shell | Backend | Rate Limit |
|---------|-------|---------|------------|
| status | `init` / `status` | `GET /assistant/status/:userId` | - |
| recommend | `recommend [limit]` | `GET /recommend/feed?limit=5` | 60/h |
| search | `search <keyword> [limit]` | `GET /skill/live-search?query=&limit=10` | 30/min |
| privacy status | `privacy status` | Local only | - |
| privacy delete-all | `privacy delete-all --confirm` | GDPR endpoint | - |
| report | `report` | Persona endpoint | 10/day |
| share | `share <reportId> <html> [locale]` | Share endpoint | 10/day |
| security | `security <skillId>` | Security endpoint | 60/h |
| clean | `clean` | `GET /user/:userId/zombies` | - |
| workflow | `workflow` | Workflow endpoint | - |
| daily | `daily` | Daily endpoint | - |
| weekly | `weekly` | Weekly endpoint | - |
| bundle | `bundle` / `bundle <id>` | Bundle endpoints | - |

## Internal Commands (AI-only)

- `clean:track <skillId>` — record uninstall event
- `bundle:track-installed <bundleId>` — record bundle install
- `recommend:track <recId> <skillId> <action>` — tune recommendations

## CONFIG.md Structure

```yaml
device_fp: <16-hex>
created_at: <ISO8601>
last_init_at: <ISO8601>
scan:
  scanned_at: <ISO8601>
  skills: [{id, name, path, installed_at, enabled, last_modified}]
  system: {os, arch, hostname, home, editors}
recommendations:
  cached_at: <ISO8601>
  ttl_hours: 24
  items: [...]
```

Do not write to CONFIG.md directly — always use shell commands.