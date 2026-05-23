#!/bin/sh
# Edge-triggered health monitor.
# Polls $HEALTH_URL every $POLL_INTERVAL seconds. On a transition from "all-ok"
# to "any-failed" (or vice versa), POSTs a Slack-compatible JSON payload to
# $WEBHOOK_URL. Stays silent during steady state.
#
# Env (with defaults):
#   HEALTH_URL      http://backend:3000/api/health
#   WEBHOOK_URL     (required)
#   POLL_INTERVAL   30   seconds
#   FAIL_THRESHOLD  3    consecutive 503s before alerting (debounce reboots)
#   INSTANCE_NAME   headless   shown in messages
set -eu

HEALTH_URL="${HEALTH_URL:-http://backend:3000/api/health}"
WEBHOOK_URL="${WEBHOOK_URL:?WEBHOOK_URL not set}"
POLL_INTERVAL="${POLL_INTERVAL:-30}"
FAIL_THRESHOLD="${FAIL_THRESHOLD:-3}"
INSTANCE_NAME="${INSTANCE_NAME:-headless}"

post() {
  # $1 = text
  text=$(printf '%s' "$1" | sed 's/"/\\"/g')
  body="{\"text\":\"[$INSTANCE_NAME] $text\"}"
  curl -fsS -X POST -H 'Content-Type: application/json' \
    -d "$body" "$WEBHOOK_URL" >/dev/null 2>&1 \
    || echo "warn: webhook POST failed" >&2
}

state=unknown   # unknown | ok | failed
fail_streak=0

echo "monitor: polling $HEALTH_URL every ${POLL_INTERVAL}s; webhook configured."

while true; do
  if body=$(curl -fsS --max-time 10 "$HEALTH_URL" 2>/dev/null); then
    fail_streak=0
    if [ "$state" != "ok" ]; then
      if [ "$state" = "failed" ]; then
        post "recovered: $body"
      fi
      state=ok
    fi
  else
    fail_streak=$((fail_streak + 1))
    if [ "$fail_streak" -ge "$FAIL_THRESHOLD" ] && [ "$state" != "failed" ]; then
      detail=$(curl -fsS --max-time 5 "$HEALTH_URL" 2>/dev/null || echo "no response")
      post "DEGRADED after ${fail_streak} failed checks: $detail"
      state=failed
    fi
  fi
  sleep "$POLL_INTERVAL"
done
