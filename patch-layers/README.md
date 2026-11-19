# Patch layers

Sometimes an app's maintainers are slow to rebuild their image, so it keeps shipping OS
packages with known, already-fixed vulnerabilities. A patch layer is a tiny local image
**on top of the official one** that only upgrades those OS packages. The app itself is unchanged.

Stackbrief understands them: the label `stackbrief.upstream` tells the scanner which official
image to check for new versions and builds, and the AI review suggests "rebuild patch layer"
or "bump BASE" when needed.

## Use one

Find the user the official image runs as: `docker image inspect -f '{{.Config.User}}' <image>`
(empty = root). Then in the app's compose file replace `image: vaultwarden/server:1.37.5` with:

```yaml
    image: local/vaultwarden:1.37.5-patched
    build:
      context: /path/to/stackbrief/patch-layers/debian   # or alpine
      pull: true
      args:
        BASE: "vaultwarden/server:1.37.5"
        RUN_AS: root
```

`docker compose build --pull vaultwarden && docker compose up -d --no-deps vaultwarden`

## Routine
- **Rebuild** (new OS fixes or a newer official build):
  `docker pull <BASE> && docker compose build --pull <service> && docker compose up -d --no-deps <service>`
  (the `docker pull` keeps the local base tag current, which the scanner compares with the registry)
- **New app version:** change `BASE` and the `image:` tag together, then rebuild.
- **Stop patching:** put back `image: <official>` and delete the `build:` block.

## Limits
- Only OS packages. CVEs in the app's own libraries (npm, pip, Go modules) need the app's maintainers.
- Test after switching: health, login, the app's main function. Upgrading libraries under an app is
  usually safe on a stable distro, but not guaranteed.
- A Go binary bundled in an image can sometimes be recompiled from source with a current Go in a
  multi-stage build (e.g. a healthcheck helper); see docs/patch-layer-recipes.md.
