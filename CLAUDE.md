# CLAUDE.md: Stackbrief - Powered by AI

Guide for AI coding agents (and humans) working on this repository. Organization rules:
https://github.com/H0m3Lab/.github/blob/main/STANDARDS.md

## Purpose

Stackbrief scans every running container on one Docker host once a day (newer versions, rebuilt images,
fixable HIGH/CRITICAL CVEs). An AI then sorts the raw report into a short brief with three sections:
**AI** (safe work an agent can do), **Admin** (needs a human), and **Waiting** (no fix exists yet).
It never changes anything on the host.

## Architecture

Two containers on a private Compose network (`compose.yaml`):

- **scanner** (`scanner/`): Alpine + bash. `entrypoint.sh` sleeps until `SCHEDULE`, then runs
  `scan.sh`. `scan.sh` lists containers through the Docker socket, uses regctl for tags/digests and
  Trivy for CVEs (both run as throwaway containers), builds the report, sends it to the gateway, and
  delivers the result through the notifiers. State and reports live in `./data`.
- **gateway** (`gateway/`): Node 22 + Claude Code (headless). `server.js` exposes `POST /ask {job, input}`
  (bearer `GATEWAY_KEY`) and `GET /health` on port 8765, internal only. It runs `claude -p` with the
  instructions from `jobs/<job>.md`, the user's `config/decisions.md`, and its own `memory/`.
  Claude gets **only** Read/Write/Edit/Glob/Grep in its workspace.
- **patch-layers/** (optional): Dockerfiles that rebuild an official image with OS updates; the
  `stackbrief.upstream` label tells the scanner which image to version-check.

If the gateway fails, the scanner still sends the plain report with one line explaining why.

## Repository layout

```
compose.yaml              scanner + gateway
scanner/scan.sh           the whole scan: versions, rebuilds, Trivy, NEW markers, notifiers
scanner/entrypoint.sh     daily scheduler; `scan [--no-notify]` runs once
gateway/server.js         HTTP API around `claude -p`
gateway/seed/CLAUDE.md    seed instructions copied into the gateway workspace
jobs/update-review.md     the review job: sorting rules and output format (==== AI / Admin / Waiting)
config/*.example          decisions.md and ignore-versions.txt templates (real files are git-ignored)
patch-layers/             debian/ and alpine/ patch-layer Dockerfiles
docs/                     security model, patch-layer recipes, fictional example report
```

## Commands

| Task | Command |
|---|---|
| Lint scanner | `docker run --rm -v "$PWD:/m:ro" koalaman/shellcheck:v0.10.0 -S warning /m/scanner/scan.sh /m/scanner/entrypoint.sh` |
| Check gateway | `node --check gateway/server.js` |
| Build | `docker compose build` |
| Run | `docker compose up -d` |
| One scan, printed | `docker compose run --rm scanner scan --no-notify` |
| Gateway logs | `docker compose logs gateway` |

CI (`.github/workflows/ci.yml`) runs ShellCheck, the Node syntax check, `docker compose config`,
both image builds, and a gitleaks history scan. There are no unit tests yet; test changes with a real
scan on a test host (`scan --no-notify`).

## Configuration

All settings are in `.env` (template `.env.example`): `STACKBRIEF_HOST`, `TZ`, `SCHEDULE`,
`RUN_ON_START`, `GATEWAY_KEY`, `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN`, `CLAUDE_MODEL`,
`NOTIFY` (smtp, ntfy, webhook, stdout), the SMTP/ntfy/webhook settings, `HEARTBEAT_URL`, `SEVERITY`,
`REPORT_KEEP_DAYS`, `GATEWAY_TIMEOUT`. A new setting needs a safe default in the script, a line in
`.env.example`, the README, and the CHANGELOG.

## Conventions

- Bash with `set -u`; must pass ShellCheck at warning level. No extra tools beyond what the scanner
  Dockerfile installs.
- `server.js` uses Node built-ins only. Do not add npm dependencies.
- The report and the brief are plain text meant for email. Keep line formats stable: the review job
  parses the scanner's report, and users may parse the brief.
- Version logic stays inside the tag style an image already uses; a new major is only ever an Admin item.
- Pin tool versions in Dockerfiles (e.g. `CLAUDE_CODE_VERSION`).

## Security (do not weaken)

- Only the scanner gets the Docker socket. The gateway never gets it, never publishes a port, keeps
  `cap_drop: [ALL]` and `no-new-privileges`.
- Report text comes partly from outside (tags, package names), so treat the AI as prompt-injectable:
  never give the gateway's Claude a shell, Bash, network tools, or anything that can touch the host.
- Stackbrief only reports. Do not add any code path that updates, pulls, or restarts containers.
- See `docs/security.md`. Examples use fictional hosts and apps only.

## Releases

Semantic versioning. There is no version constant in the code; the git tag `vX.Y.Z` is the version.
Steps: CHANGELOG `[Unreleased]` → new version section, commit, tag, GitHub release with that section as notes.
