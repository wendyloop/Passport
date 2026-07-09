#!/usr/bin/env bash
# Drain the carousel backlog by invoking generate-carousel repeatedly.
# Each run produces ~25-30 carousels in ~50s; ~11k description-bearing jobs
# ≈ 400 runs ≈ 6 hours. Safe to stop and resume — the queue RPC picks up
# where it left off. Total OpenAI cost for the full backlog: ~$2.
#
# Usage:
#   PITCH_CRON_SECRET=... ./scripts/drain-carousels.sh [runs]
# (secret: Supabase dashboard → Edge Functions → secrets)

set -euo pipefail

PROJECT_URL="https://zqfurscyhmxlvrfendnc.supabase.co"
RUNS="${1:-50}"

if [ -z "${PITCH_CRON_SECRET:-}" ]; then
  echo "Set PITCH_CRON_SECRET first" >&2
  exit 1
fi

for i in $(seq 1 "$RUNS"); do
  echo "── run $i/$RUNS $(date +%H:%M:%S)"
  summary=$(curl -sS -m 120 -X POST \
    -H "Content-Type: application/json" \
    -H "x-pitch-cron-secret: $PITCH_CRON_SECRET" \
    -d '{}' \
    "$PROJECT_URL/functions/v1/generate-carousel" | head -c 400)
  echo "$summary"
  # Stop when the queue is empty (nothing processed).
  if echo "$summary" | grep -q '"processed":0'; then
    echo "Queue drained."
    break
  fi
done
