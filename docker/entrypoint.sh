#!/usr/bin/env bash
set -euo pipefail

RUN_INTERVAL_SECONDS=${RUN_INTERVAL_SECONDS:-3600}

run_once() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting CompleteARR run..."
  pwsh ./CompleteARR_Launchers/CompleteARR_Launch_All_Scripts.ps1
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] CompleteARR run finished."
}

while true; do
  run_once
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sleeping for ${RUN_INTERVAL_SECONDS} seconds..."
  sleep "$RUN_INTERVAL_SECONDS"
done