#!/usr/bin/env bash
set -euo pipefail

RUN_INTERVAL_SECONDS=${RUN_INTERVAL_SECONDS:-3600}
STATUS_FILE=${STATUS_FILE:-/app/CompleteARR_Logs/run_status.json}

write_status() {
  local status="$1"
  local started_at="$2"
  local finished_at="$3"
  local next_run="$4"
  printf '{"status":"%s","startedAt":"%s","finishedAt":"%s","nextRun":"%s"}\n' \
    "$status" "$started_at" "$finished_at" "$next_run" > "$STATUS_FILE"
}

run_once() {
  local started_at
  local finished_at
  local next_run

  started_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  next_run="$(date -u -d "+${RUN_INTERVAL_SECONDS} seconds" '+%Y-%m-%dT%H:%M:%SZ')"
  write_status "running" "$started_at" "" "$next_run"

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting CompleteARR run..."
  pwsh ./CompleteARR_Launchers/CompleteARR_Launch_All_Scripts.ps1
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] CompleteARR run finished."

  finished_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  next_run="$(date -u -d "+${RUN_INTERVAL_SECONDS} seconds" '+%Y-%m-%dT%H:%M:%SZ')"
  write_status "idle" "$started_at" "$finished_at" "$next_run"
}

node /app/ui/server.js &

while true; do
  run_once
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sleeping for ${RUN_INTERVAL_SECONDS} seconds..."
  sleep "$RUN_INTERVAL_SECONDS"
done