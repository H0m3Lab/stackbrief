# Security notes

## The scanner has the Docker socket
Listing containers and running Trivy/regctl needs `/var/run/docker.sock`, which is root-equivalent
on the host. Keep the scanner image small and auditable: it is one shell script (`scanner/scan.sh`)
on Alpine with curl, jq and the Docker CLI. It never starts, stops or changes your containers. The only
containers it runs are short-lived `regclient/regctl` and `aquasec/trivy` (pinned tags in `.env`).

## The AI has nothing that can act
The gateway runs Claude Code with `--tools Read,Write,Edit,Glob,Grep`, working directory = its own
workspace volume. No Bash, no web fetch, no Docker socket, no host mounts, no published ports,
all capabilities dropped, `no-new-privileges`. The worst a hostile string in a report could do is
make the AI write a misleading brief, which is why the brief is advice that you read before acting.

## The gateway key
The gateway is a shared service, so only apps you put on its Docker network (`claude`) can reach it,
and every `/ask` needs `Authorization: Bearer $GATEWAY_KEY` (at least 32 characters, compared in
constant time). Give the key only to apps you trust to spend your AI quota. Don't publish its
port or put it behind a reverse proxy.

## What leaves your network
- To registries: image names (tag listings and digests).
- To Trivy's database mirror: database downloads only (scanning is local).
- To Anthropic: the text report (image names, versions, CVE IDs, container names, your
  decisions.md). No secrets, environment variables or file contents.
- To your notifier: the brief.

## Updating Stackbrief itself
The scanner reports on its own container and the gateway's too, so you'll see when an image needs a
rebuild (`docker compose build --pull && docker compose up -d`, in the repository folder and in `gateway/`). The Claude Code version is pinned with the
build arg `CLAUDE_CODE_VERSION`.
