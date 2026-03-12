#!/usr/bin/env bash
# PostToolUse hook: checks Netlify Function files for common issues.
# Reads Write tool JSON from stdin, inspects the written file.
# Always exits 0 (warn but never block).

set -euo pipefail

# Read JSON payload from stdin
INPUT=$(cat)

# Extract file_path from the JSON
FILE_PATH=$(echo "$INPUT" | grep -oP '"file_path"\s*:\s*"([^"]*)"' | head -1 | sed 's/.*: *"//;s/"$//')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Only activate for netlify function files (*.ts, *.js, *.mts)
case "$FILE_PATH" in
  */netlify/functions/*.ts|*/netlify/functions/*.js|*/netlify/functions/*.mts) ;;
  *) exit 0 ;;
esac

# Skip files in lib/ subdirectory (shared utilities)
case "$FILE_PATH" in
  */netlify/functions/lib/*) exit 0 ;;
esac

# Verify the file exists
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

CONTENT=$(cat "$FILE_PATH")
WARNINGS=0

# Check for missing CORS handling
if ! echo "$CONTENT" | grep -qE 'OPTIONS|Access-Control'; then
  echo "[netlify-functions] WARNING: No CORS handling detected in $(basename "$FILE_PATH")." >&2
  echo "  → Add OPTIONS preflight handling or use createHandler() wrapper." >&2
  WARNINGS=$((WARNINGS + 1))
fi

# Check for missing error handling
if ! echo "$CONTENT" | grep -qE '\btry\b|\bcatch\b'; then
  echo "[netlify-functions] WARNING: No try/catch error handling in $(basename "$FILE_PATH")." >&2
  echo "  → Wrap handler logic in try/catch to prevent unhandled errors." >&2
  WARNINGS=$((WARNINGS + 1))
fi

# Check for missing TypeScript type imports (info level)
if [[ "$FILE_PATH" == *.ts || "$FILE_PATH" == *.mts ]]; then
  if ! echo "$CONTENT" | grep -qE '^\s*import\s+.*type|:\s*\w+'; then
    echo "[netlify-functions] INFO: No TypeScript type annotations detected in $(basename "$FILE_PATH")." >&2
    echo "  → Consider adding type imports for request/response shapes." >&2
  fi
fi

if [ "$WARNINGS" -gt 0 ]; then
  echo "[netlify-functions] $WARNINGS warning(s) found. See references/handler-patterns.md for patterns." >&2
fi

exit 0
