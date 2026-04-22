# Skill Lifecycle Model

## Stages

```
Install → First use → Active → Declining → Zombie → Uninstall
```

| Stage | Trigger | Behavior |
|-------|---------|----------|
| Install | Skill directory exists | Record install time + path |
| First use | First invocation | Measure activation delay |
| Activation timeout | No call within 7 days of install | Flag `activation_timeout` |
| Active | ≥2 calls in 7 days | Compute frequency, detect sequences |
| Declining | This week < 50% of last week | Internal flag |
| Zombie | No call in 30 days | Flag `zombie`, surface in `clean` |
| Uninstall | User-triggered | Record reason, backup to `trash/` |

## Activation Rate Formula

```
activation_rate = active_skills / total_installed_skills
```

Report as percentage in status overview.