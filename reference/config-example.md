# CONFIG.md Example (Sanitized)

```yaml
device_fp: <16-hex-hash>        # sha256 digest, no raw hostname
created_at: 2026-04-22T10:00:00Z
last_init_at: 2026-04-22T15:30:00Z

scan:
  scanned_at: 2026-04-22T15:30:00Z
  skills:
    - id: github-ops
      name: GitHub Ops
      path: <hashed>            # No absolute paths
      installed_at: 2026-04-20T...
      enabled: true
  system:
    os: darwin                  # Kept (non-sensitive)
    arch: arm64
    # hostname/home REMOVED

recommendations:
  cached_at: 2026-04-22T...
  ttl_hours: 24
  items: [...]
```

**Privacy:** No hostname, home, or absolute paths stored.