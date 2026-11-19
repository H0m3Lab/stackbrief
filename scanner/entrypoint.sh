#!/bin/bash
# Stackbrief scanner: runs scan.sh once a day at $SCHEDULE (HH:MM, container TZ).
#   docker compose run --rm scanner scan [--no-notify]   -> one scan right now
set -u
if [ "${1:-}" = "scan" ]; then shift; exec /app/scan.sh "$@"; fi
SCHEDULE=${SCHEDULE:-07:15}
[[ "$SCHEDULE" =~ ^[0-2][0-9]:[0-5][0-9]$ ]] || { echo "SCHEDULE must be HH:MM, got '$SCHEDULE'"; exit 1; }
[ "${RUN_ON_START:-false}" = "true" ] && { /app/scan.sh || echo "scan failed (exit $?)"; }
while :; do
  now=$(date +%s); next=$(date -d "today $SCHEDULE" +%s)
  [ "$next" -le "$now" ] && next=$(date -d "tomorrow $SCHEDULE" +%s)
  echo "$(date '+%F %T') next scan at $(date -d "@$next" '+%F %T %Z')"
  sleep $((next - now))
  /app/scan.sh || echo "$(date '+%F %T') scan failed (exit $?)"
done
