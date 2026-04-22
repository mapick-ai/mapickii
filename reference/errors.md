# Error Handling Reference

## Shell Error Codes

| Code | Meaning | AI Action |
|------|---------|-----------|
| `missing_argument` | Required arg not supplied | Re-prompt user |
| `protected_skill` | Tried to uninstall mapickii/mapick/tasa | Refuse gracefully |
| `service_unreachable` | Backend down / network fail | Suggest retry later |
| `unknown_command` | Typos / unsupported | Suggest `/mapickii help` |
| `disabled_in_local_mode` | Consent declined | Show opt-in message |
| `consent_required` | First install | Run consent flow |

Render errors in user's language. Never echo JSON verbatim.

## Bundle Install Failure Playbook

| Failure | Action |
|---------|--------|
| `clawhub: command not found` | Stop; link to openclaw.io; ask retry |
| Network timeout / DNS fail | Skip current, continue; summarize at end |
| Permission denied | Report path; suggest sudo; don't auto-sudo |
| "already installed" (exit 0) | Count as success |
| Unknown error | Report first 200 chars stderr; continue |

If ALL commands fail → do NOT call `bundle:track-installed`.

## Persona Report Limits

- Backend 429 → "Rate limit exceeded (10/day). Try tomorrow."
- HTML > 200KB → "Report too large. Ask AI to regenerate shorter version."