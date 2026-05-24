#!/bin/bash
# BurnRate hook — pipe this as your Claude Code statusLine.
# Writes rate limit data for the BurnRate status bar app.
# ~/.claude/settings.json: "statusLine": {"type":"command","command":"~/.config/burnrate/hook.sh"}

input=$(cat)

FH=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
SD=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

if [ -n "$FH" ] && [ -n "$SD" ]; then
    printf '{"five_hour_pct":%s,"seven_day_pct":%s,"updated_at":%s}\n' \
        "$FH" "$SD" "$(date +%s)" > ~/.burnrate-data.json
fi
