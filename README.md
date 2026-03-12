# Netlify Functions — Serverless API Patterns Plugin

[![Version](https://img.shields.io/badge/version-1.0.0-blue?style=flat-square)](https://github.com/JHyeok5/claude-plugin-netlify-functions)
[![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey?style=flat-square)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-blueviolet?style=flat-square)]()

Scaffold and implement production-ready Netlify Functions with built-in security, error handling, and TypeScript patterns.

## The Problem

```
New function created → no CORS → frontend gets blocked
                     → no try/catch → unhandled errors crash silently
                     → no auth → endpoint exposed to anyone
                     → different patterns per function → codebase inconsistency
```

Each developer reinvents the same boilerplate. When a project has 20+ functions, conventions drift.

## The Solution

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Build registry│ --> │ 27 functions │ --> │ Create new   │ --> │ Hook warns:  │
│ fn-registry.sh│     │ analyzed     │     │ function     │     │ "27/27 use   │
└──────────────┘     └──────────────┘     └──────────────┘     │ createHandler│
         │                   │                                  │ — use it too"│
         └── registry.json ──┘── patterns: supabase auth ──────┘──────────────┘
             (type, auth,         handler path,
              CORS per fn)        common imports)
```

## Key Features

| Feature | Description |
|---------|-------------|
| 4 Function Types | API endpoints, webhooks, scheduled (cron), background tasks |
| Pattern Detection | Scans existing functions for createHandler, auth provider, common imports |
| Auto-Check Hook | Warns on missing CORS, error handling, suggests project patterns |
| Function Registry | `.netlify-fn/registry.json` — inventory with type, auth, patterns |
| Auth Provider Detection | Auto-detects Supabase, Firebase, Auth0, Clerk usage |
| Convention Enforcement | "27/27 functions use createHandler() — use it here too" |
| History Tracking | Function count and pattern snapshots across registry builds |

## Installation

```bash
# From marketplace
/plugin install netlify-functions@JHyeok5

# Or clone directly
git clone https://github.com/JHyeok5/claude-plugin-netlify-functions.git
claude --plugin-dir ./claude-plugin-netlify-functions
```

> **Note**: Restart Claude Code after installation to activate hooks.

## Usage

```
/netlify-functions:netlify-functions
```

Or describe your need — auto-triggers on Netlify tasks:

- "Create a new API endpoint"
- "Add a Stripe webhook handler"
- "Set up a daily cron function"
- "Add authentication to my Netlify function"

### Build Registry (recommended on first use)

```bash
bash scripts/fn-registry.sh /path/to/project
```

This scans `netlify/functions/` and creates `.netlify-fn/registry.json` with detected patterns.

## How It Works

```
[Registry Build — fn-registry.sh]
  1. Scan netlify/functions/*.ts|js (skip lib/ subdirectory)
  2. Classify each function: api | webhook | scheduled | background
  3. Detect per-function: hasAuth, hasCors, hasErrorHandling, usesCreateHandler
  4. Detect project patterns: auth provider, handler path, common imports
  5. Save to .netlify-fn/registry.json + append history

[Hooks (automatic on file Write)]
  New function created → check for:
    1. CORS handling (OPTIONS/Access-Control)
    2. Error handling (try/catch)
    3. TypeScript type annotations
    4. Handler wrapper usage (if project uses createHandler)
    5. Auth provider match (if project uses supabase/firebase/etc.)
  → Skip CORS/error warnings if handler wrapper detected
  → Show pattern stats: "27/27 functions use createHandler()"
```

## Patterns Included

| Pattern | Use Case | Features |
|---------|----------|----------|
| Universal Handler | Any endpoint | CORS, method check, error handling, body parsing |
| Webhook Handler | Stripe, GitHub, Apple | Signature verification, event routing |
| Scheduled Function | Cron jobs | Daily cleanup, cache refresh, reports |
| Auth-Protected | User data endpoints | Token verification, user context |
| Error Codes | All functions | Consistent error response format |

## Supported Auth Providers

| Provider | Verification Method |
|----------|-------------------|
| Supabase | `supabase.auth.getUser(token)` |
| Firebase | `admin.auth().verifyIdToken(token)` |
| Auth0 | JWKS + jsonwebtoken |
| Clerk | `clerkClient.verifyToken(token)` |
| Custom JWT | `jsonwebtoken.verify(token, secret)` |

## Auto-Check Hook

When installed, the plugin monitors new Netlify Function files:

| Check | Without Registry | With Registry |
|-------|-----------------|---------------|
| Missing CORS | Warns always | Skips if handler wrapper detected |
| Missing try/catch | Warns always | Skips if handler wrapper detected |
| TypeScript types | Warns always | Same |
| Handler wrapper | — | "27/27 use createHandler() — use it too" |
| Auth provider | — | "This project uses supabase for auth" |

The hook gets smarter after `fn-registry.sh` builds the project profile.

## Self-Improvement

The plugin creates `.netlify-fn/` in your project:

```
.netlify-fn/
└── registry.json  ← function inventory + patterns + history
```

### What the Registry Detects

```json
{
  "functions": [
    { "name": "iap-verify", "type": "webhook", "hasAuth": true, "usesCreateHandler": true }
  ],
  "patterns": {
    "usesCreateHandler": true,
    "handlerPath": "netlify/functions/lib/handler.ts",
    "authProvider": "supabase",
    "commonImports": ["./lib/handler", "./lib/supabase", "./lib/response"]
  },
  "history": [
    { "timestamp": "...", "functionCount": 27, "withCors": 27, "withAuth": 25 }
  ]
}
```

## Script Output Example

```
$ bash scripts/fn-registry.sh .

[fn-registry] Found 27 function file(s) in /project/netlify/functions
[fn-registry] Registry written to /project/.netlify-fn/registry.json
[fn-registry] Functions: 27 | CORS: 9 | ErrorHandling: 23 | Auth: 27
[fn-registry] Pattern: createHandler() used by 27/27 functions
[fn-registry] Auth provider: supabase
```

**Hook output (new function without wrapper):**
```
[netlify-functions] WARNING: No CORS handling detected in new-api.ts.
  -> Add OPTIONS preflight handling or use createHandler() wrapper.
[netlify-functions] WARNING: No try/catch error handling in new-api.ts.
  -> Wrap handler logic in try/catch to prevent unhandled errors.
[netlify-functions] WARNING: This project uses createHandler() wrapper
  (see netlify/functions/lib/handler.ts). Consider using it here too.
  -> 27/27 functions use createHandler().
[netlify-functions] INFO: This project uses supabase for auth.
  Consider using the same provider here.
```

## Plugin Structure

```
claude-plugin-netlify-functions/
├── .claude-plugin/
│   └── plugin.json              ← plugin manifest
├── skills/
│   └── netlify-functions/
│       └── SKILL.md             ← skill definition (scaffold guide)
├── hooks/
│   └── hooks.json               ← PostToolUse hook config
├── scripts/
│   ├── fn-registry.sh           ← standalone registry builder
│   └── function-check-hook.sh   ← hook script (registry-aware)
├── references/
│   ├── handler-patterns.md      ← createHandler, webhook, auth patterns
│   └── configuration.md         ← netlify.toml, TypeScript, env vars
├── README.md
└── LICENSE
```

## Requirements

- Claude Code CLI
- Netlify project (any framework)
- bash (for scripts)
- jq (optional — enhances registry management, graceful fallback without it)

## License

MIT
