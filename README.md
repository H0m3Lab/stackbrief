# Stackbrief - Powered by AI

**Turns the daily wall of "updates available" and CVE noise from your Docker host into a short,
ready-to-act brief.**

Every day Stackbrief checks every running container for newer versions, rebuilt images and
known vulnerabilities that already have a fix. An AI then reads that raw report and sorts each
item into three groups:

| Group | Meaning |
|---|---|
| **AI** | Safe patches, minor upgrades and rebuilds: a numbered list you paste into your AI coding agent (e.g. Claude Code) to carry out, one by one, with backups and tests |
| **Admin** | Things that need you: major-version migrations, judgment calls, anything your rules say a human decides |
| **Waiting** | Findings nobody can fix yet, because the app's maintainers haven't shipped a fix. Listed so you stop worrying about them |

It never changes anything on its own. You stay in charge: paste the AI section to start the work, or ignore it.

```
==== AI ====
On my-server, do these one at a time. For each: snapshot or back up its data, read the release
notes, update, test the app, update your docs. Stop and ask me if the release notes mention
breaking changes.
1. nginx-proxy-manager: 2.16.0 -> 2.17.1  [internet-facing, 8 critical CVEs]
2. vaultwarden: 1.37.4 -> 1.37.5  [internet-facing, 1 critical]
3. mariadb 11.4.13 (wordpress-db): pull + recreate newer build, stay on 11.4
4. uptime-kuma: 2.5.9 -> 2.5.12  [internal, 9 critical]
Back up, test and validate each change.

==== Admin ====
1. Postgres 17 -> 18 migration (app-db): planned, decide when.

==== Waiting ====
- freescout: 6 critical in PHP libraries, no newer image
- immich_postgres: pinned by Immich, fixed only via Immich releases
```

A full example message is in [docs/example-report.txt](docs/example-report.txt).

## How it works

```
 ┌──────────── scanner (daily) ────────────┐        ┌──────── gateway ────────┐
 │ docker ps → every image you run          │ report │ Claude Code, headless   │
 │ regctl   → newer tags, rebuilt digests   │ ─────► │ job: update-review      │
 │ Trivy    → HIGH/CRITICAL CVEs with fixes │ ◄───── │ + your decisions.md     │
 └──────────────┬──────────────────────────┘ review │ + its own memory        │
                │                                    └─────────────────────────┘
                ▼
     email / ntfy / webhook / stdout:  AI · Admin · Waiting  +  full report
```

- **Scanner:** a small shell job. Version logic stays within the tag style you use
  (`v1.2.3`, `1.2.3-alpine`, linuxserver `-lsNNN`...). Same-major bumps are actionable;
  a newer major is only mentioned as a planned migration. It marks findings that are NEW since the last run.
- **Gateway:** Claude Code in headless mode behind an internal HTTP API with per-job instructions.
  It keeps its own notes (`memory/`), so it learns your stack's recurring quirks over time.
- **Your rules:** `config/decisions.md`, in plain language. For example: which apps are
  internet-facing, "MariaDB stays on 11.4 LTS", "staging before production".
- **Fallback:** if the AI is unreachable or returns something odd, you still get the plain
  report, with one line saying why.

## Quick start

```bash
git clone https://github.com/H0m3Lab/stackbrief.git && cd stackbrief
cp .env.example .env && chmod 600 .env          # set GATEWAY_KEY, an AI login, NOTIFY
cp config/decisions.md.example config/decisions.md && chmod 644 config/decisions.md   # the AI reads it as a non-root user
cp config/ignore-versions.txt.example config/ignore-versions.txt
docker compose up -d --build
docker compose run --rm scanner scan --no-notify  # first scan now, printed to the terminal
```

The first run takes a while (Trivy downloads its database; roughly 30-60 s per image).
After that it runs daily at `SCHEDULE`.

**AI login:** set `ANTHROPIC_API_KEY` (pay per use), or `CLAUDE_CODE_OAUTH_TOKEN` from
`claude setup-token` if you use a Claude subscription. Check Anthropic's terms for your plan
before using it for unattended automation. A daily review is one short request.

Reports are kept in `data/reports/` (`YYYY-MM-DD.txt`, `-review.txt`, `-security.txt` with every finding).

## Security model

The two containers deliberately have very different powers:

| | scanner | gateway (the AI) |
|---|---|---|
| Docker socket | **yes** (needed to list containers and run Trivy/regctl) | **no** |
| Shell / host access | its own shell script only | **none**: Claude gets only Read/Write/Edit/Glob/Grep in its own workspace |
| Network | registries, Trivy DB, your notifier | Anthropic API only; no published ports |
| Acts on findings | never | never: it only writes text |

Report text partly comes from outside (image tags, package names), so the AI is treated as
something that could be prompt-injected. That's why it gets **no tools that can touch the host**.
The actual fixing happens later, in *your* agent session, after *you* paste the list.
Details: [docs/security.md](docs/security.md).

## Patch layers (optional)

When maintainers are slow to rebuild, their images keep shipping already-fixed OS
vulnerabilities. [patch-layers/](patch-layers/README.md) has tiny Dockerfiles that rebuild an
official image with current OS updates. Stackbrief follows the `stackbrief.upstream` label, so
version checks still track the official image, and the AI suggests rebuilds when needed.

## Configuration

All settings are in `.env` (see `.env.example`): schedule, host name, notifiers (`smtp`, `ntfy`,
`webhook`, `stdout`; several at once), severity, report retention, heartbeat URL, model.
Jobs are plain Markdown in `jobs/`; edit `jobs/update-review.md` to change how items are sorted
or the wording of the brief.

## Limits

- One Docker host per install. Run one per host.
- Only images in registries regctl can read (Docker Hub, GHCR, Quay, ... including anonymous rate limits).
- Trivy's `--ignore-unfixed` is used: only vulnerabilities that already have a fix are reported.
- The AI can be wrong. It sorts and explains; *you* (and your agent session) verify before changing anything.

## License

MIT - see [LICENSE](LICENSE). Stackbrief uses [Claude Code](https://claude.com/claude-code) by
Anthropic, [Trivy](https://github.com/aquasecurity/trivy) and [regclient](https://github.com/regclient/regclient).
It is an independent project, not affiliated with or endorsed by Anthropic or Aqua Security.
