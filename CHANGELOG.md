# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **The Claude gateway is now its own project, [H0m3Lab/claude-gateway](https://github.com/H0m3Lab/claude-gateway)**: one shared Claude
  container that your other self-hosted apps can use too, with one memory. Stackbrief runs only the scanner
  and reaches the gateway via `GATEWAY_URL` (default `http://claude:8765`) on `GATEWAY_NETWORK`
  (default `claude`). Its review job ships as `jobs/update-review.md`, copied into the gateway's `jobs/`.
- **Upgrading from 0.1.0:** `docker compose down`; install claude-gateway with your AI login, `GATEWAY_KEY`
  and `decisions.md` (from `config/decisions.md`); copy `jobs/update-review.md` into its `jobs/`; remove the
  AI login lines from Stackbrief's `.env`; `docker compose up -d --build`. To keep the AI's memory, copy
  the old `gateway-data` volume's contents into the gateway's `claude-data` volume.

### Added
- `## Brief instructions` in `decisions.md` replaces the first line of the AI section, so the
  wording can be changed without editing the tracked job file.
- `compose.override.yaml` is git-ignored and documented for local paths and networks.

## [0.1.0] - 2026-11-19

First public release.

### Added
- Scanner: newer versions within the image's tag style, rebuilt images, and fixable HIGH/CRITICAL
  CVEs (Trivy), with NEW markers since the last run and per-CVE package lines.
- Gateway: Claude Code in headless mode behind an internal HTTP API, with read/write-only tools in its
  own workspace and its own memory.
- `update-review` job that sorts the report into AI, Admin, and Waiting sections using your
  `decisions.md`; plain report as fallback when the AI is unreachable.
- Notifiers: SMTP, ntfy, webhook, stdout; optional heartbeat URL.
- Patch layers for Debian and Alpine images, followed through the `stackbrief.upstream` label.
- Security model and patch-layer docs, fictional example report, MIT license.
- Project docs (CLAUDE.md, this changelog) and CI (ShellCheck, compose check, Docker builds, secret scan).

### Fixed
- Line endings forced to LF so the scripts work when the repository is cloned on Windows.

[Unreleased]: https://github.com/H0m3Lab/stackbrief/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/H0m3Lab/stackbrief/releases/tag/v0.1.0
