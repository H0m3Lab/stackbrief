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
 ┌──────────── scanner (daily) ────────────┐        ┌─── Claude gateway ──────┐
 │ docker ps → every image you run          │ report │ Claude Code, headless   │
 │ regctl   → newer tags, rebuilt digests   │ ─────► │ job: update-review      │
 │ Trivy    → HIGH/CRITICAL CVEs with fixes │ ◄───── │ + your decisions.md     │
 └──────────────┬──────────────────────────┘ review │ + its own memory        │
                │                                    │ (shared: other apps can │
                │                                    │  send it jobs too)      │
                │                                    └─────────────────────────┘
                ▼
     email / ntfy / webhook / stdout:  AI · Admin · Waiting  +  full report
```

- **Scanner:** a small shell job. Version logic stays within the tag style you use
  (`v1.2.3`, `1.2.3-alpine`, linuxserver `-lsNNN`...). Same-major bumps are actionable;
  a newer major is only mentioned as a planned migration. It marks findings that are NEW since the last run.
- **Claude gateway** ([H0m3Lab/claude-gateway](https://github.com/H0m3Lab/claude-gateway), a separate project): Claude Code in headless
  mode behind an internal HTTP API with per-job instructions. **Run it as its own container**, so your
  other self-hosted apps can use the same Claude for their own jobs. It keeps its own notes (`memory/`),
  so it learns your setup's recurring quirks over time. Stackbrief is just one of its users (job
  `update-review`, shipped here in [jobs/](jobs/update-review.md)).
- **Your rules:** the gateway's `decisions.md`, in plain language. For example: which apps are
  internet-facing, "MariaDB stays on 11.4 LTS", "staging before production".
- **Fallback:** if the AI is unreachable or returns something odd, you still get the plain
  report, with one line saying why.

## Quick start

1. **The Claude gateway** (skip if you already run it): install
   [H0m3Lab/claude-gateway](https://github.com/H0m3Lab/claude-gateway#install). It's a separate container that your other apps can use too.
2. **Stackbrief:**

```bash
git clone https://github.com/H0m3Lab/stackbrief.git && cd stackbrief
cp jobs/update-review.md ../claude-gateway/jobs/   # Stackbrief's job, into the gateway's jobs/ folder
cp .env.example .env && chmod 600 .env             # the gateway's GATEWAY_KEY, NOTIFY, schedule
cp config/ignore-versions.txt.example config/ignore-versions.txt
docker compose up -d --build
docker compose run --rm scanner scan --no-notify   # first scan now, printed to the terminal
```

Add Stackbrief's rules to the gateway's `decisions.md`: which apps are internet-facing, version lines you
stay on, and optionally the first line of the brief. See [docs/decisions-example.md](docs/decisions-example.md).
The scanner reaches the gateway at `http://claude:8765` on the Docker network `claude`; if yours is
elsewhere, set `GATEWAY_URL` and `GATEWAY_NETWORK` in `.env`. After updating Stackbrief, copy
`jobs/update-review.md` into the gateway again.

The first run takes a while (Trivy downloads its database; roughly 30-60 s per image).
After that it runs daily at `SCHEDULE`.

The AI login (API key or Claude subscription token) is set in the gateway. A daily review is one short request.

Reports are kept in `data/reports/` (`YYYY-MM-DD.txt`, `-review.txt`, `-security.txt` with every finding).

## Security model

The scanner and the gateway deliberately have very different powers:

| | scanner | gateway (the AI) |
|---|---|---|
| Docker socket | **yes** (needed to list containers and run Trivy/regctl) | **no** |
| Shell / host access | its own shell script only | **none**: Claude gets only Read/Write/Edit/Glob/Grep in its own workspace |
| Network | registries, Trivy DB, your notifier | Anthropic API only; no published ports; reachable only from apps on its `claude` network, with the key |
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
`webhook`, `stdout`; several at once), severity, report retention, heartbeat URL, gateway address.
The AI login and model are set in the gateway.
The review job is plain Markdown ([jobs/update-review.md](jobs/update-review.md)); edit your copy in the
gateway's `jobs/` folder to change how items are sorted or the wording of the brief.
To change only the instruction line your agent reads first, add a `## Brief instructions`
section to the gateway's `decisions.md` (see [docs/decisions-example.md](docs/decisions-example.md)).

**Local changes to the containers** (extra networks, storing data elsewhere, reaching a heartbeat
monitor on another Docker network) go in `compose.override.yaml`, which is git-ignored and picked up
automatically by `docker compose`. For example:

```yaml
services:
  scanner:
    volumes: [/srv/appdata/stackbrief/data:/data]
    networks: [gateway, monitoring]        # e.g. so HEARTBEAT_URL can use http://uptime-kuma:3001/...
networks:
  monitoring: {external: true}
```

## Limits

- One Docker host per install. Run one per host.
- Only images in registries regctl can read (Docker Hub, GHCR, Quay, ... including anonymous rate limits).
- Trivy's `--ignore-unfixed` is used: only vulnerabilities that already have a fix are reported.
- The AI can be wrong. It sorts and explains; *you* (and your agent session) verify before changing anything.

## Troubleshooting

- **The brief has no AI sections, only the plain report:** the line at the top says why. Usually the AI
  login (`ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`) or `GATEWAY_KEY` (at least 32 characters, same
  value here and in the gateway), the gateway has no `update-review` job, or the scanner can't reach the
  gateway (`GATEWAY_URL`, `GATEWAY_NETWORK`). Check `docker logs claude`.
- **The first scan is very slow:** Trivy downloads its database and scans each image once; later runs
  are faster.
- **Version checks fail for Docker Hub images:** regctl uses anonymous access, so Docker Hub's rate
  limits apply; the scanner retries once. Run the scan at a quiet time, away from big pulls.
- **Nothing arrives by email:** test delivery with `NOTIFY=stdout`, then check the SMTP settings (TLS is required).
- **`network claude declared as external, but could not be found`:** start the gateway first, or set
  `GATEWAY_NETWORK` to the network your gateway is on.

## Releases and contributing

Versions and changes: [Releases](https://github.com/H0m3Lab/stackbrief/releases) and [CHANGELOG.md](CHANGELOG.md).
Developer and AI-agent guide: [CLAUDE.md](CLAUDE.md). Bug reports and ideas are welcome as issues; see the
[contribution guide](https://github.com/H0m3Lab/.github/blob/main/CONTRIBUTING.md). Report security
problems privately through the **Security** tab.

## License

MIT - see [LICENSE](LICENSE). Stackbrief uses [Claude Code](https://claude.com/claude-code) by
Anthropic, [Trivy](https://github.com/aquasecurity/trivy) and [regclient](https://github.com/regclient/regclient).
It is an independent project, not affiliated with or endorsed by Anthropic or Aqua Security.
