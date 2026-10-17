#!/usr/bin/env bash
# Checks every agent brief has the frontmatter agent-review.yml needs, so a bad brief fails here
# instead of in someone else's PR. Files starting with "_" are shared text, not agents.
set -euo pipefail

field() { awk -v k="$1" 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} NR>1 && index($0, k":")==1 {sub(/^[^:]*:[ \t]*/, ""); print; exit}' "$2"; }

status=0
for brief in review-agents/*.md; do
  case "$(basename "$brief")" in _*) continue ;; esac
  model=$(field model "$brief")
  effort=$(field effort "$brief")
  turns=$(field max-turns "$brief")
  problems=()
  [ -n "$model" ] || problems+=("no model")
  case "$effort" in low|medium|high|xhigh|max) ;; *) problems+=("effort must be low, medium, high, xhigh or max") ;; esac
  [[ -z "$turns" || "$turns" =~ ^[0-9]+$ ]] || problems+=("max-turns must be a number")
  if [ ${#problems[@]} -gt 0 ]; then
    echo "::error file=$brief::$(printf '%s; ' "${problems[@]}")"
    status=1
  else
    echo "$brief: $model, effort $effort, up to ${turns:-30} turns"
  fi
done
exit $status
