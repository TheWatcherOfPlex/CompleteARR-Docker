#!/usr/bin/env sh
set -eu

RUN_INTERVAL_SECONDS=${RUN_INTERVAL_SECONDS:-3600}
LOGS_BASE=${LOGS_BASE:-/app/CompleteARR_Logs}
FULL_LOGS_DIR=${FULL_LOGS_DIR:-"${LOGS_BASE}/Full Logs"}
ERROR_LOGS_DIR=${ERROR_LOGS_DIR:-"${LOGS_BASE}/Error Logs"}
STATUS_FILE=${STATUS_FILE:-"${LOGS_BASE}/run_status.json"}
RUN_LOCK_DIR=${RUN_LOCK_DIR:-"${LOGS_BASE}/run.lock"}

# Disable Read-Host pauses inside launchers when running under Docker.
export COMPLETEARR_NO_PAUSE=${COMPLETEARR_NO_PAUSE:-1}

mkdir -p "$LOGS_BASE" "$FULL_LOGS_DIR" "$ERROR_LOGS_DIR"

organize_logs() {
  # Move any *.log files in the logs root into Full Logs.
  # (Keep run_status.json and other non-log files at the root.)
  find "$LOGS_BASE" -maxdepth 1 -type f -name "*.log" -exec mv -f {} "$FULL_LOGS_DIR" \; 2>/dev/null || true

  # Migrate any error logs that might already exist in the Full Logs folder into Error Logs.
  find "$FULL_LOGS_DIR" -maxdepth 1 -type f -name "*_ERRORS*.log" -exec mv -f {} "$ERROR_LOGS_DIR" \; 2>/dev/null || true
}

# Initial migration on startup.
organize_logs

acquire_lock() {
  mkdir "$RUN_LOCK_DIR" 2>/dev/null
}

release_lock() {
  rmdir "$RUN_LOCK_DIR" 2>/dev/null || true
}

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

  # Prevent overlapping runs (manual UI run vs scheduled run).
  if ! acquire_lock; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Run already in progress. Skipping scheduled run."
    return 0
  fi
  trap release_lock RETURN

  started_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  next_run="$(date -u -d "+${RUN_INTERVAL_SECONDS} seconds" '+%Y-%m-%dT%H:%M:%SZ')"
  write_status "running" "$started_at" "" "$next_run"

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting CompleteARR run..."
  # Ensure root stays clean even if a previous run wrote logs directly into LOGS_BASE.
  organize_logs
  pwsh ./CompleteARR_Launchers/CompleteARR_Launch_All_Scripts.ps1
  # Ensure this run's logs end up in Full Logs/Error Logs.
  organize_logs
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