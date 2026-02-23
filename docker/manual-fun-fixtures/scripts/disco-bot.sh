#!/bin/sh
set -eu

pick() {
  max="$1"
  value="$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')"
  echo $((value % max))
}

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [disco-bot] warming up the dance floor"

while true; do
  mood="$(pick 8)"
  crowd="$(pick 400)"
  tempo="$(pick 180)"
  sleep_secs=$((1 + $(pick 3)))

  case "$mood" in
    0) event="laser-beams synced with the bassline" ;;
    1) event="rubber duck DJ requested another encore" ;;
    2) event="server rack did a tiny moonwalk" ;;
    3) event="coffee machine dropped a surprise beat" ;;
    4) event="pixel confetti launched across the terminal" ;;
    5) event="silent disco mode triggered by cat paws" ;;
    6) event="vibe checksum passed with flying neon colors" ;;
    7) event="karaoke container hit a dramatic key change" ;;
  esac

  bpm=$((60 + tempo))
  crowd_size=$((12 + crowd))
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [disco-bot] bpm=${bpm} crowd=${crowd_size} event=\"${event}\""
  sleep "$sleep_secs"
done
