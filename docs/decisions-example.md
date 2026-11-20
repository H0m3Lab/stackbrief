# Stackbrief rules for the Claude gateway's decisions.md. Add these sections there and edit them.

## Internet-facing apps (fix these first)
- nginx-proxy-manager, vaultwarden, nextcloud

## Rules
- MariaDB stays on the 11.4 LTS line; 11.8 and newer majors are a planned migration -> Admin.
- Postgres major upgrades (17 -> 18) -> Admin.
- Immich server + machine-learning are always updated together, same version.
- ghcr.io/immich-app/postgres is pinned by Immich; never update it separately -> Waiting.
- WordPress: update the staging copy first, then production.

## Brief instructions
(Optional. Replaces the first line under "==== AI ====", which is what your agent reads first.)
On my-server, do these one at a time. For each: take a snapshot, read the release notes, update, test the app, update its docs page. Stop and ask me if the release notes mention breaking changes.
