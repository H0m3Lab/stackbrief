#!/bin/bash
# Stackbrief scan: one report about every running container on this Docker host.
#   1. NEWER VERSION : a higher version tag exists (same tag style; same major = act, higher major = note)
#   2. NEWER BUILD   : the tag you run was rebuilt upstream (usually OS/security patches)
#   3. SECURITY      : HIGH/CRITICAL vulnerabilities that already have a fixed version (Trivy)
# Then the report goes to the AI gateway (job "update-review"), which sorts it into
# AI / Admin / Waiting. The notification leads with that review and has the full report below.
# Never changes anything on the host.
#   scan.sh [--no-notify]     (--no-notify prints the message instead of sending it)
set -u
D=/data
CFG=/config
HOST_LABEL=${STACKBRIEF_HOST:-this Docker host}
REGCTL_IMG=${REGCTL_IMAGE:-regclient/regctl:v0.11.7}
TRIVY_IMG=${TRIVY_IMAGE:-aquasec/trivy:0.76.2}
TRIVY_CACHE=${TRIVY_CACHE_VOLUME:-stackbrief-trivy-cache}
SEVERITY=${SEVERITY:-HIGH,CRITICAL}
KEEP_DAYS=${REPORT_KEEP_DAYS:-60}
GATEWAY_URL=${GATEWAY_URL:-http://claude:8765}
TODAY=$(date +%F)
mkdir -p "$D/reports" "$D/state"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
exec 9>"$D/state/lock"; flock -n 9 || { echo "a scan is already running"; exit 0; }
IGNORE=$CFG/ignore-versions.txt; [ -f "$IGNORE" ] || IGNORE=/dev/null
PREV=$D/state/prev-keys.txt; [ -f "$PREV" ] || : > "$PREV"; FIRST_RUN=0; [ -s "$PREV" ] || FIRST_RUN=1

regctl() { docker run --rm "$REGCTL_IMG" "$@" 2>/dev/null; }

# ---- inventory: configured image ref | image id | container name (stackbrief's own containers included)
docker ps -q | while read -r c; do
  docker inspect -f '{{.Config.Image}}|{{.Image}}|{{.Name}}' "$c"
done | sed 's#|/#|#' | sort > "$WORK/inv"
cut -d'|' -f1 "$WORK/inv" | sort -u > "$WORK/refs"
for f in newver newbuild sec secfull ok notes keys; do : > "$WORK/$f"; done

norm_suffix() { sed -E 's/(-r[0-9]+)?-ls[0-9]+$/-ls#/' <<<"$1"; }   # linuxserver.io build counters

while read -r ref; do
  names=$(grep -F "$ref|" "$WORK/inv" | grep "^$ref|" | cut -d'|' -f3 | sort -u | paste -sd, -)
  ids=$(grep -F "$ref|" "$WORK/inv" | grep "^$ref|" | cut -d'|' -f2 | sort -u)
  first_id=$(head -1 <<<"$ids")
  # patch layer: label stackbrief.upstream (or homelab.upstream) = the official image it was built on
  up=$(docker image inspect -f '{{with index .Config.Labels "stackbrief.upstream"}}{{.}}{{else}}{{with index .Config.Labels "homelab.upstream"}}{{.}}{{end}}{{end}}' "$first_id" 2>/dev/null)
  vref=${up:-$ref}
  repo=${vref%:*}; tag=${vref##*:}; [ "$repo" = "$vref" ] && tag=latest
  pnote=""; [ -n "$up" ] && pnote=" [patch layer: change BASE + image tag together, then rebuild]"
  [ -n "$up" ] && echo "  $ref ($names): patch layer on $up; version/rebuild checks use the official image" >> "$WORK/notes"
  local_build=0
  [ -z "$up" ] && [ "$(docker image inspect -f '{{len .RepoDigests}}' "$first_id" 2>/dev/null)" = "0" ] && local_build=1
  flagged=0

  if [ "$local_build" = 1 ]; then
    echo "  $ref ($names): built locally; version check skipped, security scan below" >> "$WORK/notes"
  else
    # -- 1. newer version tag
    if ! grep -qxF "$repo" "$IGNORE" && [[ "$tag" =~ ^(v?)([0-9]+(\.[0-9]+)*)(.*)$ ]]; then
      pre=${BASH_REMATCH[1]}; nums=${BASH_REMATCH[2]}; suf=$(norm_suffix "${BASH_REMATCH[4]}")
      ncomp=$(awk -F. '{print NF}' <<<"$nums")
      regctl tag ls "$repo" > "$WORK/tags" || { sleep 20; regctl tag ls "$repo" > "$WORK/tags"; } \
        || echo "  $ref: could not list tags (registry refused twice; checked again next run)" >> "$WORK/notes"
      cur_major=$(cut -d. -f1 <<<"$nums")
      while read -r t; do
        [[ "$t" =~ ^(v?)([0-9]+(\.[0-9]+)*)(.*)$ ]] || continue
        [ "${BASH_REMATCH[1]}" = "$pre" ] || continue
        [ "$(norm_suffix "${BASH_REMATCH[4]}")" = "$suf" ] || continue
        [ "$(awk -F. '{print NF}' <<<"${BASH_REMATCH[2]}")" = "$ncomp" ] || continue
        echo "$(cut -d. -f1 <<<"${BASH_REMATCH[2]}") $t"
      done < "$WORK/tags" > "$WORK/cands"
      best=$({ awk -v m="$cur_major" '$1==m{print $2}' "$WORK/cands"; echo "$tag"; } | sort -V | tail -1)
      top=$({ awk '{print $2}' "$WORK/cands"; echo "$tag"; } | sort -V | tail -1)
      major_note=""; [ "$top" != "$best" ] && major_note=" (new major $top also out - planned migration, not urgent)"
      if [ "$best" != "$tag" ]; then
        echo "$repo $tag -> $best$major_note  ($names)$pnote" >> "$WORK/newver"; echo "ver|$repo|$best" >> "$WORK/keys"; flagged=1
      elif [ -n "$major_note" ]; then
        echo "  $ref:$major_note" >> "$WORK/notes"
      fi
    fi
    # -- 2. newer build of the same tag (registry digest vs what runs / what the patch layer was built on)
    remote=$(regctl image digest "$vref")
    if [ -n "$remote" ]; then
      cmpids=$ids; action="pull + recreate"
      if [ -n "$up" ]; then
        cmpids=$(docker image inspect -f '{{.Id}}' "$up" 2>/dev/null || echo missing-base)
        action="rebuild patch layer (docker pull $up, then docker compose build --pull <service> and up -d --no-deps)"
      fi
      for id in $cmpids; do
        if ! docker image inspect "$id" -f '{{range .RepoDigests}}{{println .}}{{end}}' 2>/dev/null | grep -q "@$remote$"; then
          echo "$ref  has a newer build upstream (same version, usually OS/security patches) -> $action  ($names)" >> "$WORK/newbuild"
          echo "build|$ref|$remote" >> "$WORK/keys"; flagged=1; break
        fi
      done
    else
      echo "  $ref: could not read registry digest" >> "$WORK/notes"
    fi
  fi

  # -- 3. security scan of exactly what runs (each distinct image id)
  for id in $ids; do
    idnames=$(grep -F "$ref|$id|" "$WORK/inv" | cut -d'|' -f3 | sort -u | paste -sd, -)
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$TRIVY_CACHE":/root/.cache \
      "$TRIVY_IMG" image --quiet --scanners vuln --severity "$SEVERITY" --ignore-unfixed \
      --format json "$id" > "$WORK/t.json" 2>"$WORK/t.err"
    if ! jq -e . "$WORK/t.json" >/dev/null 2>&1; then
      echo "  $ref: security scan failed ($(head -c 150 "$WORK/t.err" | tr '\n' ' '))" >> "$WORK/notes"; continue
    fi
    jq -r '[.Results[]?.Vulnerabilities[]?] | unique_by(.VulnerabilityID+.PkgName)
           | sort_by(if .Severity=="CRITICAL" then 0 else 1 end) | .[]
           | "\(.Severity)|\(.VulnerabilityID)|\(.PkgName)|\(.InstalledVersion)|\(.FixedVersion)"' "$WORK/t.json" > "$WORK/v"
    if [ -s "$WORK/v" ]; then
      crit=$(grep -c '^CRITICAL' "$WORK/v"); high=$(grep -c '^HIGH' "$WORK/v")
      # CVE keys use the repository without the tag, so a version bump doesn't re-mark old findings as NEW
      cut -d'|' -f2 "$WORK/v" | sort -u | sed "s#^#cve|$repo|#" > "$WORK/vk"
      newc=$(grep -cvxFf "$PREV" "$WORK/vk"); [ "$FIRST_RUN" = 1 ] && newc=0
      build=""; [ "$(wc -w <<<"$ids")" -gt 1 ] && build=" [build ${id#sha256:}"; build="${build:0:20}${build:+]}"
      newtxt=""; [ "$newc" -gt 0 ] && newtxt=", $newc new"
      { echo "$ref$build ($idnames): $crit critical, $high high$newtxt"
        grep '^CRITICAL' "$WORK/v" | cut -d'|' -f2,3 | sort -u -t'|' -k1,1 | head -3 | while IFS='|' read -r cve pkg; do
          echo "      critical: $cve in $pkg"
        done
        [ "$crit" -gt 3 ] && echo "      ... $((crit-3)) more critical"
        # package names let the AI tell OS packages (patch layer can fix) from app libraries (it can't)
        jq -r '[.Results[]? | select(.Vulnerabilities) | "\(.Class)" as $c | .Vulnerabilities[] | "\($c):\(.PkgName)"] | unique
               | group_by(split(":")[0]) | map("\(.[0]|split(":")[0]) \(map(split(":")[1])|.[0:8]|join(","))\(if length>8 then ",..." else "" end)") | join("; ")' \
          "$WORK/t.json" | sed 's/^/      packages: /'
      } >> "$WORK/sec"
      sed "s#^#$ref ($idnames)|#" "$WORK/v" >> "$WORK/secfull"
      cat "$WORK/vk" >> "$WORK/keys"; flagged=1
    fi
  done
  [ "$flagged" = 0 ] && echo "  $ref" >> "$WORK/ok"
done < "$WORK/refs"

# ---- assemble the report
mark_new() { while read -r line; do
  first=$(awk '{print $1}' <<<"$line")
  if [ "$FIRST_RUN" = 1 ] || grep -q "^$1|${first%:*}" "$PREV"; then echo "  $line"; else echo "  NEW $line"; fi
done; }
nv=$(wc -l < "$WORK/newver"); nb=$(wc -l < "$WORK/newbuild"); ns=$(grep -c '^[^ ]' "$WORK/sec")
nnew=$(sort -u "$WORK/keys" | grep -cvxFf "$PREV"); [ "$FIRST_RUN" = 1 ] && nnew=0
SUBJ="[Stackbrief] $HOST_LABEL $TODAY: $nv new version(s), $nb rebuild(s), $ns image(s) with fixable security issues"
[ "$nnew" -gt 0 ] && SUBJ="$SUBJ - $nnew new since last run"
[ "$((nv+nb+ns))" = 0 ] && SUBJ="[Stackbrief] $HOST_LABEL $TODAY: everything up to date"
{
  echo "Stackbrief update report for $HOST_LABEL. Nothing was changed."
  echo "NEW = not in the previous report."
  echo
  echo "== 1. NEWER VERSIONS AVAILABLE ($nv)"; [ "$nv" = 0 ] && echo "  none" || mark_new ver < "$WORK/newver"
  echo
  echo "== 2. NEWER BUILD OF THE SAME VERSION ($nb)"; [ "$nb" = 0 ] && echo "  none" || mark_new build < "$WORK/newbuild"
  echo
  echo "== 3. SECURITY: $SEVERITY WITH A FIX AVAILABLE ($ns images)"
  echo "   (a fix usually arrives through item 1 or 2; if neither lists the app, its maintainers haven't shipped one yet)"
  [ "$ns" = 0 ] && echo "  none" || sed 's/^\([^ ]\)/  \1/' "$WORK/sec"
  echo
  echo "== Up to date, no fixable findings"; [ -s "$WORK/ok" ] && cat "$WORK/ok" || echo "  none"
  if [ -s "$WORK/notes" ]; then echo; echo "== Notes"; cat "$WORK/notes"; fi
  echo
  echo "-- Stackbrief scan, $(date '+%F %T %Z'). Full findings: reports/$TODAY-security.txt"
} > "$WORK/body"
cp "$WORK/body" "$D/reports/$TODAY.txt"
{ echo "image|severity|id|package|installed|fixed in"; cat "$WORK/secfull"; } > "$D/reports/$TODAY-security.txt"

# ---- AI review (gateway job update-review). Any failure -> plain report with a one-line reason.
review_note=""
if [ -n "${GATEWAY_KEY:-}" ]; then
  jq -n --rawfile input "$WORK/body" '{job:"update-review", input:$input}' > "$WORK/req.json"
  if curl -sS -m "${GATEWAY_TIMEOUT:-900}" -H "Authorization: Bearer $GATEWAY_KEY" -H 'Content-Type: application/json' \
       --data-binary @"$WORK/req.json" "$GATEWAY_URL/ask" > "$WORK/rev.json" 2>"$WORK/reverr" \
     && jq -e '.ok == true' "$WORK/rev.json" >/dev/null 2>&1; then
    jq -r '.text' "$WORK/rev.json" | sed -n '/^==== AI ====/,$p' > "$WORK/review"
    [ -s "$WORK/review" ] || review_note="AI review came back in an unexpected format (see the gateway's history)."
  else
    review_note="AI review unavailable: $( (jq -r '.error // empty' "$WORK/rev.json" 2>/dev/null; cat "$WORK/reverr") | tr '\n' ' ' | head -c 200)"
  fi
else
  review_note="AI review skipped: GATEWAY_KEY is not set."
fi
if [ -s "$WORK/review" ]; then
  cp "$WORK/review" "$D/reports/$TODAY-review.txt"
  { echo "Stackbrief for $HOST_LABEL - AI-reviewed. Nothing was changed."
    echo "To start: paste everything from '==== AI ====' down to (not including) '==== Admin ====' into your AI coding agent."
    echo; cat "$WORK/review"
    echo; echo; echo "==================== Full report ===================="; echo
    cat "$WORK/body"; } > "$WORK/msg"
else
  { echo "($review_note)"; echo; cat "$WORK/body"; } > "$WORK/msg"
fi
find "$D/reports" -name '*.txt' -mtime +"$KEEP_DAYS" -delete
sort -u "$WORK/keys" > "$PREV"

# ---- deliver (NOTIFY = comma list of smtp, ntfy, webhook, stdout)
[ "${1:-}" = "--no-notify" ] && { cat "$WORK/msg"; exit 0; }
rc=0
for n in $(tr ',' ' ' <<<"${NOTIFY:-stdout}"); do
  case $n in
    smtp)
      { printf 'From: Stackbrief <%s>\r\nTo: %s\r\nSubject: %s\r\nDate: %s\r\nMessage-ID: <%s.%s@stackbrief>\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n' \
          "$MAIL_FROM" "$MAIL_TO" "$SUBJ" "$(date -R)" "$(date +%s)" "$RANDOM"
        sed 's/$/\r/' "$WORK/msg"; } > "$WORK/mail"
      curl -sS --ssl-reqd --url "$SMTP_URL" --user "$SMTP_USER:$SMTP_PASS" --mail-from "$MAIL_FROM" \
        --mail-rcpt "$MAIL_TO" --upload-file "$WORK/mail" || { echo "smtp delivery failed"; rc=1; } ;;
    ntfy)
      curl -sS -o /dev/null -H "Title: $SUBJ" ${NTFY_TOKEN:+-H "Authorization: Bearer $NTFY_TOKEN"} \
        -H "Filename: stackbrief-$TODAY.txt" -T "$WORK/msg" "$NTFY_URL" || { echo "ntfy delivery failed"; rc=1; } ;;
    webhook)
      jq -n --arg subject "$SUBJ" --rawfile text "$WORK/msg" '{subject:$subject, text:$text}' \
        | curl -sS -o /dev/null -H 'Content-Type: application/json' --data-binary @- "$WEBHOOK_URL" || { echo "webhook delivery failed"; rc=1; } ;;
    stdout) echo "$SUBJ"; cat "$WORK/msg" ;;
    *) echo "unknown NOTIFY target '$n'"; rc=1 ;;
  esac
done
[ "$rc" = 0 ] && [ -n "${HEARTBEAT_URL:-}" ] && curl -fsS -m 10 -o /dev/null "$HEARTBEAT_URL"
exit $rc
