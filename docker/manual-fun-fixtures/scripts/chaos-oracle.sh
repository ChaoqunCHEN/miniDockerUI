#!/bin/sh
set -eu

pick() {
  max="$1"
  value="$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')"
  echo $((value % max))
}

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [chaos-oracle] oracle online and looking into the log void"

while true; do
  forecast="$(pick 7)"
  latency="$(pick 150)"
  rockets="$(pick 6)"
  noodles="$(pick 12)"
  sleep_secs=$((2 + $(pick 4)))

  case "$forecast" in
    0) omen="today is ideal for refactoring before lunch" ;;
    1) omen="all green tests may summon surprise optimism" ;;
    2) omen="one flaky test will disappear when observed" ;;
    3) omen="a TODO comment will become self-aware" ;;
    4) omen="merge conflicts likely, snacks strongly advised" ;;
    5) omen="shipping velocity boosted by rubber-duck debugging" ;;
    6) omen="sudden clarity detected in stack traces" ;;
  esac

  latency_ms=$((40 + latency))
  rockets_launched=$((1 + rockets))
  noodle_index=$((88 + noodles))
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [chaos-oracle] latency_ms=${latency_ms} rockets=${rockets_launched} noodle_index=${noodle_index} omen=\"${omen}\""
  sleep "$sleep_secs"
done
