# Changelog

All notable changes to Mapickii will be documented in this file.

## v0.0.2 - 2026-04-23

### Fixed

- `install.sh` now downloads the tarball to a file before extracting, with `curl --retry 3 --retry-delay 2`. Previously the streamed `curl | tar` pipeline could leave a truncated archive on transient network drops, causing spurious "Failed to download" errors.

## v0.0.1 - 2026-04-23

First public release of Mapickii — the Mapick ecosystem butler.

### Supported platform

- OpenClaw (`~/.openclaw/skills/mapickii/`)
