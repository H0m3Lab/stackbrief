# Claude gateway

**Claude Code as one shared service for your self-hosted apps.** Part of Stackbrief, but not tied to it.

Run it once as its own container. Any app on your Docker host can then send it a job over HTTP and get text
back: Stackbrief's daily update review, a summary, sorting or classification, a draft. It keeps one
workspace with your standing rules (`decisions.md`) and its own notes per job (`memory/`), so it
learns your setup over time, across all the apps that use it.

## Run it

```bash
cd gateway
cp .env.example .env && chmod 600 .env                     # GATEWAY_KEY + an AI login
cp decisions.md.example decisions.md && chmod 644 decisions.md
docker compose up -d --build
```

It creates the Docker network `claude`. No ports are published.

**AI login:** set `ANTHROPIC_API_KEY` (pay per use), or `CLAUDE_CODE_OAUTH_TOKEN` from
`claude setup-token` if you use a Claude subscription. Check Anthropic's terms for your plan before
using it for unattended automation.

## Use it from an app

1. Put the app on the `claude` network (in its compose file: `networks: [claude]` plus
   `networks: {claude: {external: true}}`).
2. Add a job: `jobs/<name>.md` holds the instructions, written like a prompt. The material to work
   on is passed separately and appears inside `<input>`. Jobs are read on every call, so no restart
   is needed.
3. Call it:

```bash
curl -s -H "Authorization: Bearer $GATEWAY_KEY" -H 'Content-Type: application/json' \
     -d '{"job": "my-job", "input": "text to work on"}' http://claude:8765/ask
# -> {"ok": true, "text": "...", "duration_ms": 41000, "turns": 3, "cost_usd": 0.04}
```

`GET /health` (no key) shows whether it's busy, which jobs exist and which login it uses. Jobs run
one at a time, in order. Every call is saved in `history/<job>/` inside the data volume (the last 200 per job).

## What Claude can do in here

Only Read, Write, Edit, Glob and Grep, inside its own workspace. It has no shell, no Docker, no network
tools and no access to the host. App input often contains text from outside (package names, emails,
web pages), so it's treated as possibly hostile. **Don't add tools that can act on your systems.**
Have the calling app or a person act on the answer instead. Details: [../docs/security.md](../docs/security.md).

## Files

| Path | What |
|---|---|
| `jobs/*.md` | one instruction file per job (`update-review.md` is Stackbrief's) |
| `decisions.md` | your standing rules, read on every job (git-ignored; template `decisions.md.example`) |
| volume `claude-data` | Claude's login state, `workspace/` (CLAUDE.md, `memory/`), `history/` |
