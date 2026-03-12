#!/usr/bin/env bash
# PostToolUse hook: checks Netlify Function files for common issues.
# Reads Write tool JSON from stdin, inspects the written file.
# If a .netlify-fn/registry.json exists, uses it for project-adaptive warnings.
# Always exits 0 (warn but never block).

set -euo pipefail

# Read JSON payload from stdin
INPUT=$(cat)

# Extract file_path from the JSON
FILE_PATH=$(echo "$INPUT" | grep -oP '"file_path"\s*:\s*"([^"]*)"' | head -1 | sed 's/.*: *"//;s/"$//')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Only activate for netlify function files (*.ts, *.js, *.mts, *.mjs)
case "$FILE_PATH" in
  */netlify/functions/*.ts|*/netlify/functions/*.js|*/netlify/functions/*.mts|*/netlify/functions/*.mjs) ;;
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

# ── Registry lookup ──────────────────────────────────────────────────────────
# Walk up from the file to find .netlify-fn/registry.json

REGISTRY_FILE=""
REGISTRY_DIR=""
search_dir="$(dirname "$FILE_PATH")"
# Walk up at most 10 levels to find .netlify-fn/registry.json
for _ in $(seq 1 10); do
  if [ -f "$search_dir/.netlify-fn/registry.json" ]; then
    REGISTRY_FILE="$search_dir/.netlify-fn/registry.json"
    REGISTRY_DIR="$search_dir/.netlify-fn"
    break
  fi
  parent="$(dirname "$search_dir")"
  if [ "$parent" = "$search_dir" ]; then
    break  # reached filesystem root
  fi
  search_dir="$parent"
done

# Registry-derived values (defaults for when no registry exists)
REG_USES_CREATE_HANDLER=false
REG_HANDLER_PATH=""
REG_AUTH_PROVIDER=""
REG_CREATE_HANDLER_COUNT=0
REG_TOTAL_FUNCTIONS=0

if [ -n "$REGISTRY_FILE" ]; then
  # Try jq first, fallback to grep-based extraction
  if command -v jq &>/dev/null; then
    REG_USES_CREATE_HANDLER=$(jq -r '.patterns.usesCreateHandler // false' "$REGISTRY_FILE" 2>/dev/null || echo "false")
    REG_HANDLER_PATH=$(jq -r '.patterns.handlerPath // ""' "$REGISTRY_FILE" 2>/dev/null || echo "")
    REG_AUTH_PROVIDER=$(jq -r '.patterns.authProvider // ""' "$REGISTRY_FILE" 2>/dev/null || echo "")
    REG_TOTAL_FUNCTIONS=$(jq -r '.functions | length' "$REGISTRY_FILE" 2>/dev/null || echo "0")
    REG_CREATE_HANDLER_COUNT=$(jq -r '[.functions[] | select(.usesCreateHandler == true)] | length' "$REGISTRY_FILE" 2>/dev/null || echo "0")
  else
    # Fallback: grep-based extraction (best-effort)
    if grep -q '"usesCreateHandler"\s*:\s*true' "$REGISTRY_FILE" 2>/dev/null; then
      # Check the patterns-level usesCreateHandler (appears after "patterns")
      # This is approximate — grep can't reliably distinguish nested JSON keys
      REG_USES_CREATE_HANDLER=true
    fi
    REG_HANDLER_PATH=$(grep -oP '"handlerPath"\s*:\s*"([^"]*)"' "$REGISTRY_FILE" 2>/dev/null | head -1 | sed 's/.*"handlerPath"\s*:\s*"//;s/"$//' || echo "")
    REG_AUTH_PROVIDER=$(grep -oP '"authProvider"\s*:\s*"([^"]*)"' "$REGISTRY_FILE" 2>/dev/null | head -1 | sed 's/.*"authProvider"\s*:\s*"//;s/"$//' || echo "")
    # Count function entries (approximate)
    REG_TOTAL_FUNCTIONS=$(grep -c '"name"\s*:' "$REGISTRY_FILE" 2>/dev/null || echo "0")
    REG_CREATE_HANDLER_COUNT=$(grep -c '"usesCreateHandler"\s*:\s*true' "$REGISTRY_FILE" 2>/dev/null || echo "0")
    # Subtract 1 from createHandler count if patterns-level key was counted
    if [ "$REG_USES_CREATE_HANDLER" = "true" ] && [ "$REG_CREATE_HANDLER_COUNT" -gt 0 ]; then
      REG_CREATE_HANDLER_COUNT=$((REG_CREATE_HANDLER_COUNT - 1))
    fi
  fi
  # Normalize null/empty
  [ "$REG_HANDLER_PATH" = "null" ] && REG_HANDLER_PATH=""
  [ "$REG_AUTH_PROVIDER" = "null" ] && REG_AUTH_PROVIDER=""
fi

# Helper: detect if file uses a handler wrapper (createHandler, withHandler, etc.)
uses_handler_wrapper() {
  echo "$CONTENT" | grep -qE 'createHandler|create_handler|withHandler|wrapHandler' && return 0
  echo "$CONTENT" | grep -qE "from\s+['\"]\./(lib/)?handler['\"]" && return 0
  return 1
}

# ── Check: CORS handling ─────────────────────────────────────────────────────

if ! echo "$CONTENT" | grep -qE 'OPTIONS|Access-Control|cors|CORS'; then
  # If a handler wrapper is used, it handles CORS — skip this warning
  if ! uses_handler_wrapper; then
    echo "[netlify-functions] WARNING: No CORS handling detected in $(basename "$FILE_PATH")." >&2
    echo "  -> Add OPTIONS preflight handling or use createHandler() wrapper." >&2
    WARNINGS=$((WARNINGS + 1))
  fi
fi

# ── Check: Error handling ────────────────────────────────────────────────────

if ! echo "$CONTENT" | grep -qE '\btry\b|\bcatch\b|errorResponse|error_response'; then
  # If a handler wrapper is used, it handles errors — skip this warning
  if ! uses_handler_wrapper; then
    echo "[netlify-functions] WARNING: No try/catch error handling in $(basename "$FILE_PATH")." >&2
    echo "  -> Wrap handler logic in try/catch to prevent unhandled errors." >&2
    WARNINGS=$((WARNINGS + 1))
  fi
fi

# ── Check: TypeScript types (info level) ─────────────────────────────────────

if [[ "$FILE_PATH" == *.ts || "$FILE_PATH" == *.mts ]]; then
  if ! echo "$CONTENT" | grep -qE '^\s*import\s+.*type|:\s*\w+'; then
    echo "[netlify-functions] INFO: No TypeScript type annotations detected in $(basename "$FILE_PATH")." >&2
    echo "  -> Consider adding type imports for request/response shapes." >&2
  fi
fi

# ── Registry-based checks ────────────────────────────────────────────────────

if [ -n "$REGISTRY_FILE" ]; then

  # Check: project uses handler wrapper but this file doesn't
  if [ "$REG_USES_CREATE_HANDLER" = "true" ]; then
    if ! uses_handler_wrapper; then
      handler_hint=""
      if [ -n "$REG_HANDLER_PATH" ]; then
        handler_hint=" (see $REG_HANDLER_PATH)"
      fi
      echo "[netlify-functions] WARNING: This project uses createHandler() wrapper${handler_hint}. Consider using it here too." >&2
      echo "  -> $REG_CREATE_HANDLER_COUNT/$REG_TOTAL_FUNCTIONS functions use createHandler()." >&2
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # Check: project uses a specific auth provider — suggest matching pattern
  if [ -n "$REG_AUTH_PROVIDER" ]; then
    # Only suggest if this function seems to need auth but doesn't use the project's provider
    if echo "$CONTENT" | grep -qiE 'auth|token|Bearer|authorization'; then
      if ! echo "$CONTENT" | grep -qiE "$REG_AUTH_PROVIDER"; then
        echo "[netlify-functions] INFO: This project uses $REG_AUTH_PROVIDER for auth. Consider using the same provider here." >&2
      fi
    fi
  fi

fi

# ── Summary ──────────────────────────────────────────────────────────────────

if [ "$WARNINGS" -gt 0 ]; then
  echo "[netlify-functions] $WARNINGS warning(s) found. See references/handler-patterns.md for patterns." >&2
fi

exit 0
