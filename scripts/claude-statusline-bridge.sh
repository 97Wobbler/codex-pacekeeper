#!/bin/bash

set -u

input=$(cat)
cache_file="${CODEX_PACEKEEPER_CLAUDE_CACHE:-$HOME/Library/Application Support/Codex Pacekeeper/claude-rate-limits.json}"
cache_dir=$(dirname "$cache_file")
now=$(date +%s)

payload=$(
  printf '%s' "$input" | jq -c --argjson timestamp "$now" '
    def usage_window($window):
      if $window == null then
        null
      else
        {
          used_percentage: ($window.used_percentage // $window.utilization // $window.used_percent),
          resets_at: ($window.resets_at // $window.reset_at)
        }
        | select(.used_percentage != null and .resets_at != null)
      end;

    {
      schema_version: 1,
      source: "claude-code-statusline",
      timestamp: $timestamp,
      five_hour: usage_window(.rate_limits.five_hour),
      seven_day: usage_window(.rate_limits.seven_day)
    }
    | select(.five_hour != null and .seven_day != null)
  ' 2>/dev/null
) || exit 0

if [ -z "$payload" ] || [ "$payload" = "null" ]; then
  exit 0
fi

mkdir -p "$cache_dir" || exit 0
tmp_file="$cache_file.$$.tmp"

umask 077
if printf '%s\n' "$payload" > "$tmp_file"; then
  mv "$tmp_file" "$cache_file"
else
  rm -f "$tmp_file"
fi
