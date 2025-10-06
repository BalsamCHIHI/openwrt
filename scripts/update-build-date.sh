#!/bin/sh
# Update version.date with current Unix timestamp and show human-readable format

VERSION_DATE_FILE="$(dirname "$0")/../version.date"

echo "Updating build date..."
DATE_NOW=$(date +%s)
echo "$DATE_NOW" > "$VERSION_DATE_FILE"
echo "New build date: $DATE_NOW"
echo "Human-readable: $(date -d @$DATE_NOW)"
