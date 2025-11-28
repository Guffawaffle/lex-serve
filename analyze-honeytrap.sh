#!/bin/bash
# Honeytrap Log Analyzer

LOG="/srv/lex-serve/nginx/logs/honeytrap.log"

echo "=== Honeytrap Attack Summary ==="
echo ""

if [ ! -f "$LOG" ] || [ ! -s "$LOG" ]; then
    echo "No attacks logged yet."
    exit 0
fi

echo "Total Attacks: $(wc -l < "$LOG")"
echo ""

echo "--- Attack Types ---"
jq -r '.attack_type' "$LOG" 2>/dev/null | sort | uniq -c | sort -rn
echo ""

echo "--- Top Attackers (by IP) ---"
jq -r '.remote_addr' "$LOG" 2>/dev/null | sort | uniq -c | sort -rn | head -10
echo ""

echo "--- Countries ---"
jq -r '.cf_ipcountry // "unknown"' "$LOG" 2>/dev/null | sort | uniq -c | sort -rn
echo ""

echo "--- Most Targeted URIs ---"
jq -r '.request_uri' "$LOG" 2>/dev/null | sort | uniq -c | sort -rn | head -10
echo ""

echo "--- Recent Attacks (last 5) ---"
tail -5 "$LOG" | jq -r '"\(.timestamp) | \(.remote_addr) (\(.cf_ipcountry // "?")) | \(.request_method) \(.request_uri) | \(.http_user_agent)"'
