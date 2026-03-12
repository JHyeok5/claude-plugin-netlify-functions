#!/usr/bin/env bash
# fn-registry.sh — Standalone Netlify Functions registry builder.
# Scans netlify/functions/ and builds .netlify-fn/registry.json.
#
# Usage: bash fn-registry.sh [project-root]
#   project-root defaults to current working directory.
#
# Output: <project-root>/.netlify-fn/registry.json
# Pure bash + jq (optional, graceful fallback to manual JSON).

set -euo pipefail

PROJECT_ROOT="${1:-.}"
# Resolve to absolute path
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

FUNCTIONS_DIR="$PROJECT_ROOT/netlify/functions"
CONFIG_DIR="$PROJECT_ROOT/.netlify-fn"
REGISTRY_FILE="$CONFIG_DIR/registry.json"

# ── Helpers ──────────────────────────────────────────────────────────────────

# Check if jq is available
HAS_JQ=false
if command -v jq &>/dev/null; then
  HAS_JQ=true
fi

# Escape a string for JSON (handles quotes, backslashes, newlines)
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# Return "true" or "false" string for JSON boolean
json_bool() {
  if [ "$1" = "true" ] || [ "$1" = "1" ]; then
    echo "true"
  else
    echo "false"
  fi
}

timestamp_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ── Validation ───────────────────────────────────────────────────────────────

if [ ! -d "$FUNCTIONS_DIR" ]; then
  echo "[fn-registry] No netlify/functions/ directory found at $PROJECT_ROOT" >&2
  echo "[fn-registry] Nothing to scan." >&2
  exit 0
fi

# Collect function files (top-level .ts/.js/.mts/.mjs, excluding lib/ and config files)
FUNCTION_FILES=()
for f in "$FUNCTIONS_DIR"/*.ts "$FUNCTIONS_DIR"/*.js "$FUNCTIONS_DIR"/*.mts "$FUNCTIONS_DIR"/*.mjs; do
  [ -f "$f" ] || continue
  # Skip config/metadata files
  case "$(basename "$f")" in
    tsconfig.json|tsconfig.*.json|package.json|*.config.ts|*.config.js|*.config.mts|*.config.mjs|*.d.ts) continue ;;
  esac
  FUNCTION_FILES+=("$f")
done

if [ ${#FUNCTION_FILES[@]} -eq 0 ]; then
  echo "[fn-registry] No function files found in $FUNCTIONS_DIR" >&2
  exit 0
fi

echo "[fn-registry] Found ${#FUNCTION_FILES[@]} function file(s) in $FUNCTIONS_DIR"

# ── Create config directory ──────────────────────────────────────────────────

mkdir -p "$CONFIG_DIR"

# ── Analyze each function ────────────────────────────────────────────────────

# Arrays to collect data for pattern detection
ALL_IMPORTS=()
CREATE_HANDLER_COUNT=0
AUTH_PROVIDERS_FOUND=()

# JSON fragments for each function
FUNCTION_ENTRIES=()

for filepath in "${FUNCTION_FILES[@]}"; do
  filename="$(basename "$filepath")"
  name="${filename%.*}"  # strip extension
  content="$(cat "$filepath")"
  relative_path="netlify/functions/$filename"

  # ── Detect function type ──

  func_type="api"

  # Scheduled: has Config export with schedule
  if echo "$content" | grep -qE '(export\s+(const\s+)?config|Config)' && \
     echo "$content" | grep -qE 'schedule\s*[=:]'; then
    func_type="scheduled"
  fi

  # Webhook: has signature verification patterns
  if echo "$content" | grep -qiE 'signature|verify.*webhook|webhook.*verif|hmac|x-hub-signature|stripe-signature|jws|signedPayload'; then
    func_type="webhook"
  fi

  # Background: filename ends with -background
  if [[ "$name" == *-background ]]; then
    func_type="background"
  fi

  # ── Detect auth ──

  has_auth=false
  if echo "$content" | grep -qiE 'auth|token|verify.*user|getUser|verifyIdToken|jwt\.verify|Bearer|authorization|service_role'; then
    has_auth=true
  fi

  # ── Detect CORS ──

  has_cors=false
  if echo "$content" | grep -qE 'OPTIONS|Access-Control|cors|CORS'; then
    has_cors=true
  fi

  # ── Detect error handling ──

  has_error_handling=false
  if echo "$content" | grep -qE '\btry\b|\bcatch\b|errorResponse|error_response'; then
    has_error_handling=true
  fi

  # ── Detect handler wrapper usage ──
  # Detect createHandler, withHandler, wrapHandler, or import from handler module

  uses_create_handler=false
  if echo "$content" | grep -qE 'createHandler|create_handler|withHandler|wrapHandler'; then
    uses_create_handler=true
    CREATE_HANDLER_COUNT=$((CREATE_HANDLER_COUNT + 1))
  elif echo "$content" | grep -qE "from\s+['\"]\./(lib/)?handler['\"]"; then
    uses_create_handler=true
    CREATE_HANDLER_COUNT=$((CREATE_HANDLER_COUNT + 1))
  fi

  # ── Collect imports for pattern detection ──

  while IFS= read -r import_line; do
    # Extract the module path from import statements
    module=$(echo "$import_line" | grep -oP "from\s+['\"]([^'\"]+)['\"]" | sed "s/from\s*['\"]//;s/['\"]$//" || true)
    if [ -n "$module" ]; then
      ALL_IMPORTS+=("$module")
    fi
    # Also handle require() calls
    module=$(echo "$import_line" | grep -oP "require\s*\(\s*['\"]([^'\"]+)['\"]" | sed "s/require\s*(\s*['\"]//;s/['\"]$//" || true)
    if [ -n "$module" ]; then
      ALL_IMPORTS+=("$module")
    fi
  done < <(echo "$content" | grep -E '^\s*(import|const\s+.*=\s*require)' || true)

  # ── Detect auth provider ──

  if echo "$content" | grep -qiE '@supabase|supabase'; then
    AUTH_PROVIDERS_FOUND+=("supabase")
  fi
  if echo "$content" | grep -qiE 'firebase-admin|firebase'; then
    AUTH_PROVIDERS_FOUND+=("firebase")
  fi
  if echo "$content" | grep -qiE '@auth0|auth0'; then
    AUTH_PROVIDERS_FOUND+=("auth0")
  fi
  if echo "$content" | grep -qiE '@clerk|clerk'; then
    AUTH_PROVIDERS_FOUND+=("clerk")
  fi

  # ── Build JSON entry ──

  entry=$(cat <<ENTRY_EOF
    {
      "name": "$(json_escape "$name")",
      "file": "$(json_escape "$relative_path")",
      "type": "$(json_escape "$func_type")",
      "hasAuth": $(json_bool "$has_auth"),
      "hasCors": $(json_bool "$has_cors"),
      "hasErrorHandling": $(json_bool "$has_error_handling"),
      "usesCreateHandler": $(json_bool "$uses_create_handler")
    }
ENTRY_EOF
  )
  FUNCTION_ENTRIES+=("$entry")
done

# ── Detect patterns ─────────────────────────────────────────────────────────

# usesCreateHandler: true if majority of functions use it
TOTAL_FUNCTIONS=${#FUNCTION_FILES[@]}
uses_create_handler_pattern=false
if [ "$CREATE_HANDLER_COUNT" -gt 0 ] && [ "$CREATE_HANDLER_COUNT" -ge $((TOTAL_FUNCTIONS / 2)) ]; then
  uses_create_handler_pattern=true
fi

# handlerPath: look for the actual handler lib file
handler_path=""
for candidate in "$FUNCTIONS_DIR/lib/handler.ts" "$FUNCTIONS_DIR/lib/handler.js" \
                 "$FUNCTIONS_DIR/lib/handler.mts" "$FUNCTIONS_DIR/lib/handler.mjs"; do
  if [ -f "$candidate" ]; then
    handler_path="netlify/functions/lib/$(basename "$candidate")"
    break
  fi
done

# authProvider: most common auth provider
auth_provider=""
if [ ${#AUTH_PROVIDERS_FOUND[@]} -gt 0 ]; then
  # Find most frequent provider
  auth_provider=$(printf '%s\n' "${AUTH_PROVIDERS_FOUND[@]}" | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
fi

# commonImports: find imports used by 2+ functions (relative imports only)
COMMON_IMPORTS=()
if [ ${#ALL_IMPORTS[@]} -gt 0 ]; then
  while IFS= read -r line; do
    count=$(echo "$line" | awk '{print $1}')
    import_path=$(echo "$line" | awk '{print $2}')
    # Only include relative imports (./  ../) that appear in 2+ functions
    if [ "$count" -ge 2 ] && [[ "$import_path" == ./* || "$import_path" == ../* ]]; then
      COMMON_IMPORTS+=("$import_path")
    fi
  done < <(printf '%s\n' "${ALL_IMPORTS[@]}" | sort | uniq -c | sort -rn)
fi

# ── History: merge with existing registry ────────────────────────────────────

# Count stats for history entry
cors_count=0
error_handling_count=0
auth_count=0
for filepath in "${FUNCTION_FILES[@]}"; do
  content="$(cat "$filepath")"
  if echo "$content" | grep -qE 'OPTIONS|Access-Control|cors|CORS'; then
    cors_count=$((cors_count + 1))
  fi
  if echo "$content" | grep -qE '\btry\b|\bcatch\b|errorResponse|error_response'; then
    error_handling_count=$((error_handling_count + 1))
  fi
  if echo "$content" | grep -qiE 'auth|token|verify.*user|getUser|verifyIdToken|jwt\.verify|Bearer|authorization|service_role'; then
    auth_count=$((auth_count + 1))
  fi
done

NEW_HISTORY_ENTRY=$(cat <<HIST_EOF
    {
      "timestamp": "$(timestamp_iso)",
      "functionCount": $TOTAL_FUNCTIONS,
      "withCors": $cors_count,
      "withErrorHandling": $error_handling_count,
      "withAuth": $auth_count
    }
HIST_EOF
)

# Load existing history from registry if it exists
EXISTING_HISTORY=""
if [ -f "$REGISTRY_FILE" ] && [ "$HAS_JQ" = "true" ]; then
  EXISTING_HISTORY=$(jq -r '.history // []' "$REGISTRY_FILE" 2>/dev/null || echo "")
elif [ -f "$REGISTRY_FILE" ]; then
  # Fallback: extract history array manually (best-effort)
  # We'll keep last 10 entries max
  EXISTING_HISTORY=""
fi

# ── Build final JSON ─────────────────────────────────────────────────────────

# Build functions array
functions_json=""
for i in "${!FUNCTION_ENTRIES[@]}"; do
  if [ "$i" -gt 0 ]; then
    functions_json="${functions_json},"$'\n'
  fi
  functions_json="${functions_json}${FUNCTION_ENTRIES[$i]}"
done

# Build commonImports array
common_imports_json=""
for i in "${!COMMON_IMPORTS[@]}"; do
  if [ "$i" -gt 0 ]; then
    common_imports_json="${common_imports_json}, "
  fi
  common_imports_json="${common_imports_json}\"$(json_escape "${COMMON_IMPORTS[$i]}")\""
done
if [ -z "$common_imports_json" ]; then
  common_imports_json=""
fi

# Build history array
if [ "$HAS_JQ" = "true" ] && [ -n "$EXISTING_HISTORY" ] && [ "$EXISTING_HISTORY" != "" ] && [ "$EXISTING_HISTORY" != "[]" ] && [ "$EXISTING_HISTORY" != "null" ]; then
  # Append new entry, keep last 20
  HISTORY_JSON=$(echo "$EXISTING_HISTORY" | jq --argjson new "$NEW_HISTORY_ENTRY" '. + [$new] | .[-20:]')
else
  HISTORY_JSON="[
$NEW_HISTORY_ENTRY
  ]"
fi

# handler_path JSON value
if [ -n "$handler_path" ]; then
  handler_path_json="\"$(json_escape "$handler_path")\""
else
  handler_path_json="null"
fi

# authProvider JSON value
if [ -n "$auth_provider" ]; then
  auth_provider_json="\"$(json_escape "$auth_provider")\""
else
  auth_provider_json="null"
fi

# Assemble the full registry JSON
REGISTRY_JSON=$(cat <<REGISTRY_EOF
{
  "detectedAt": "$(timestamp_iso)",
  "functions": [
$functions_json
  ],
  "patterns": {
    "usesCreateHandler": $(json_bool "$uses_create_handler_pattern"),
    "handlerPath": $handler_path_json,
    "authProvider": $auth_provider_json,
    "commonImports": [$common_imports_json]
  },
  "history": $HISTORY_JSON
}
REGISTRY_EOF
)

# Pretty-print with jq if available, otherwise write as-is
if [ "$HAS_JQ" = "true" ]; then
  echo "$REGISTRY_JSON" | jq '.' > "$REGISTRY_FILE"
else
  echo "$REGISTRY_JSON" > "$REGISTRY_FILE"
fi

echo "[fn-registry] Registry written to $REGISTRY_FILE"
echo "[fn-registry] Functions: $TOTAL_FUNCTIONS | CORS: $cors_count | ErrorHandling: $error_handling_count | Auth: $auth_count"
if [ "$uses_create_handler_pattern" = "true" ]; then
  echo "[fn-registry] Pattern: createHandler() used by $CREATE_HANDLER_COUNT/$TOTAL_FUNCTIONS functions"
fi
if [ -n "$auth_provider" ]; then
  echo "[fn-registry] Auth provider: $auth_provider"
fi
