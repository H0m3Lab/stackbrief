# CLAUDE.md: Stackbrief - Powered by AI

Guide for AI coding agents (and humans) working on this repository. Organization rules:
https://github.com/H0m3Lab/.github/blob/main/STANDARDS.md

## Purpose

Stackbrief scans every running container on one Docker host once a day (newer versions, rebuilt images,
fixable HIGH/CRITICAL CVEs). An AI then sorts the raw report into a short brief with three sections:
**AI** (safe work an agent can do), **Admin** (needs a human), and **Waiting** (no fix exists yet).
It never changes anything on the host.

## Architecture

The scanner (`compose.yaml`) plus the separate project [H0m3Lab/claude-gateway](https://github.com/H0m3Lab/claude-gateway), a shared
Claude service other apps call too. They meet on the Docker network `claude`:

- **scanner** (`scanner/`): Alpine + bash. `entrypoint.sh` sleeps until `SCHEDULE`, then runs
  `scan.sh`. `scan.sh` lists containers through the Docker socket, uses regctl for tags/digests and
  Trivy for CVEs (both run as throwaway containers), builds the report, sends it to the gateway, and
  delivers the result through the notifiers. State and reports live in `./data`. It reaches the
  gateway at `GATEWAY_URL` (default `http://claude:8765`) on `GATEWAY_NETWORK` (default `claude`).
- **gateway** (separate repo, container `claude`): `POST /ask {job, input}` (bearer `GATEWAY_KEY`) on
  port 8765, internal only. Stackbrief only ships its job, `jobs/update-review.md`, which users copy into
  the gateway's `jobs/`. Gateway changes belong in that repo, not here.
- **patch-layers/** (optional): Dockerfiles that rebuild an official image with OS updates; the
  `stackbrief.upstream` label tells the scanner which image to version-check.

If the gateway fails, the scanner still sends the plain report with one line explaining why.

## Repository layout

```
compose.yaml              the scanner (joins the gateway's network)
scanner/scan.sh           the whole scan: versions, rebuilds, Trivy, NEW markers, notifiers
scanner/entrypoint.sh     daily scheduler; `scan [--no-notify]` runs once
jobs/update-review.md     the review job for the gateway: sorting rules and output format (==== AI / Admin / Waiting)
config/*.example          ignore-versions.txt template (real file is git-ignored)
patch-layers/             debian/ and alpine/ patch-layer Dockerfiles
docs/                     security model, patch-layer recipes, decisions example, fictional example report
```

## Commands

| Task | Command |
|---|---|
| Lint scanner | `docker run --rm -v "$PWD:/m:ro" koalaman/shellcheck:v0.10.0 -S warning /m/scanner/scan.sh /m/scanner/entrypoint.sh` |
| Build | `docker compose build` |
| Run | gateway first (its own repo), then `docker compose up -d` |
| One scan, printed | `docker compose run --rm scanner scan --no-notify` |
| Gateway logs | `docker logs claude` |

CI (`.github/workflows/ci.yml`) runs ShellCheck, `docker compose config`,
both image builds, and a gitleaks history scan. There are no unit tests yet; test changes with a real
scan on a test host (`scan --no-notify`).

## Configuration

Scanner settings are in `.env` (template `.env.example`): `STACKBRIEF_HOST`, `TZ`, `SCHEDULE`,
`RUN_ON_START`, `GATEWAY_KEY`, `GATEWAY_URL`, `GATEWAY_NETWORK`,
`NOTIFY` (smtp, ntfy, webhook, stdout), the SMTP/ntfy/webhook settings, `HEARTBEAT_URL`, `SEVERITY`,
`REPORT_KEEP_DAYS`, `GATEWAY_TIMEOUT`. The AI login and model are gateway settings. A new setting needs a safe default in the script, a line in
`.env.example`, the README, and the CHANGELOG.

## Conventions

- Bash with `set -u`; must pass ShellCheck at warning level. No extra tools beyond what the scanner
  Dockerfile installs.
- The report and the brief are plain text meant for email. Keep line formats stable: the review job
  parses the scanner's report, and users may parse the brief.
- Version logic stays inside the tag style an image already uses; a new major is only ever an Admin item.
- Pin tool versions in Dockerfiles (e.g. `CLAUDE_CODE_VERSION`).

## Security (do not weaken)

- Only the scanner gets the Docker socket. Never ask users to give the gateway the socket, a shell, or host access.
- Report text comes partly from outside (tags, package names), so treat the AI as prompt-injectable:
  never give the gateway's Claude a shell, Bash, network tools, or anything that can touch the host.
- Stackbrief only reports. Do not add any code path that updates, pulls, or restarts containers.
- See `docs/security.md`. Examples use fictional hosts and apps only.

## Releases

Semantic versioning. There is no version constant in the code; the git tag `vX.Y.Z` is the version.
Steps: CHANGELOG `[Unreleased]` → new version section, commit, tag, GitHub release with that section as notes.
