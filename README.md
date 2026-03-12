# Netlify Functions — Serverless API Patterns Plugin

Scaffold and implement production-ready Netlify Functions with built-in security, error handling, and TypeScript patterns.

## What This Plugin Does

- Scaffolds new functions with production-grade boilerplate
- Provides reusable handler wrapper (CORS, method check, error handling)
- Covers 4 function types: API endpoints, webhooks, scheduled (cron), background
- Includes auth middleware patterns for any provider (Supabase, Firebase, Auth0, Clerk)
- Tracks project patterns and suggests shared utilities

## Installation

```bash
/plugin install netlify-functions@JHyeok5
```

Or load directly:

```bash
claude --plugin-dir ./claude-plugin-netlify-functions
```

## Usage

```
/netlify-functions:netlify-functions
```

Or describe your need — auto-triggers on Netlify tasks:

- "Create a new API endpoint"
- "Add a Stripe webhook handler"
- "Set up a daily cron function"
- "Add authentication to my Netlify function"

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

## Self-Improvement

The skill creates `.netlify-fn/` in your project on first run:
- `registry.json` — inventory of all functions (name, type, route, auth)
- `patterns.json` — detected project conventions (middleware, error codes)

Subsequent runs match your project's existing style and suggest shared utility extraction.

## Requirements

- Claude Code CLI
- Netlify project (any framework)

## License

MIT
