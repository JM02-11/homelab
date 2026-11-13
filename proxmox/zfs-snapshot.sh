#!/usr/bin/env bash
# Usage: homelab-zfs-snapshot <dataset> <keep>
# Takes a recursive snapshot named auto-YYYY-MM-DD and keeps the newest <keep> of them.
set -euo pipefail
dataset=${1:?dataset}
keep=${2:-14}

zfs snapshot -r "${dataset}@auto-$(date +%F)" 2>/dev/null || true   # already taken today is fine

zfs list -H -t snapshot -o name -s creation -d 1 "$dataset" \
  | grep "@auto-" \
  | head -n -"$keep" \
  | while read -r snap; do
      zfs destroy -r "$snap"
    done
