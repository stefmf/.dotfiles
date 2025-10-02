#!/bin/bash

KEY_NAME="F13"
KEY_CODE=105
INTERVAL_MINUTES=15

function is_weekday() {
  local day=$(date +%u)
  [[ "$day" -lt 6 ]]  # 1 (Mon) to 5 (Fri)
}

function is_within_hours() {
  local hour=$(date +%H | sed 's/^0*//')
  [[ "$hour" -ge 8 && "$hour" -lt 16 ]]
}


function send_keypress() {
  osascript -e "tell application \"System Events\" to key code $KEY_CODE"
}

echo "[staygreen] Active. Sending $KEY_NAME keypress every $INTERVAL_MINUTES minutes until 4 PM."

while true; do
  if is_weekday && is_within_hours; then
    echo "[staygreen] $(date '+%a %H:%M') → Sent $KEY_NAME keypress."
    send_keypress
  elif ! is_weekday; then
    echo "[staygreen] $(date '+%a %H:%M') → Weekend. Exiting."
    break
  else
    echo "[staygreen] $(date '+%a %H:%M') → Office hours over. Exiting."
    break
  fi
  sleep $((INTERVAL_MINUTES * 60))
done
