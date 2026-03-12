---
name: netlify-functions
description: Scaffold and implement Netlify Functions (serverless) with production-grade patterns. This skill should be used when creating API endpoints, webhooks, scheduled functions, or background tasks on Netlify. Covers handler patterns, CORS, authentication, rate limiting, error handling, TypeScript configuration, and deployment. Works with Netlify Functions v2 (Web API standard) and v1 (callback-style).
license: MIT
metadata:
  author: JHyeok5
  version: "1.0.0"
  tags: [netlify, serverless, functions, api, backend, webhooks, typescript]
  platforms: Claude, ChatGPT, Gemini
---

# Netlify Functions — Serverless API Patterns

Scaffold and implement production-ready Netlify Functions with built-in security, error handling, and TypeScript support. From quick prototypes to production APIs.

## When to Use

- **New API endpoint**: Create a serverless REST endpoint
- **Webhook handler**: Receive callbacks from Stripe, GitHub, Apple, etc.
- **Scheduled task**: Cron-based background functions (cleanup, sync, notifications)
- **Form handler**: Process form submissions server-side
- **Auth proxy**: Protect third-party API keys behind a server function
- **Database operations**: Server-side queries that bypass client-side restrictions

## Quick Start

### What is a Netlify Function?

A Netlify Function is a small piece of server code that runs when someone visits a specific URL. Think of it as a "mini server" that:
- Only runs when needed (no server to maintain)
- Costs nothing when idle (free tier: 125K requests/month)
- Deploys automatically with the site (no separate hosting)

**Example**: A contact form that sends an email.
Without a function, the frontend would need to expose an email API key.
With a function, the key stays on the server, hidden from users.

### Create a Function in 3 Steps

**Step 1** — Create the file:

```
netlify/functions/hello.ts
```

**Step 2** — Write the handler:

```typescript
// Netlify Functions v2 — Web API standard (recommended)
export default async (req: Request) => {
  const name = new URL(req.url).searchParams.get("name") || "World";

  return new Response(
    JSON.stringify({ message: `Hello, ${name}!` }),
    { headers: { "Content-Type": "application/json" } }
  );
};
```

**Step 3** — Add a clean URL in `netlify.toml`:

```toml
[[redirects]]
  from = "/api/hello"
  to = "/.netlify/functions/hello"
  status = 200
```

Now accessible at: `https://your-site.netlify.app/api/hello?name=Claude`

### Test Locally

```bash
npx netlify dev
# → http://localhost:8888/api/hello?name=Claude
```

## Function Types

| Type | Use Case | Trigger | Example |
|------|----------|---------|---------|
| **API endpoint** | REST operations | HTTP request | User CRUD, search |
| **Webhook** | External service callback | External POST | Stripe payment, GitHub push |
| **Scheduled** | Periodic background task | Cron schedule | Daily cleanup, cache refresh |
| **Background** | Long-running async work | HTTP (returns immediately) | Image processing, email batch |

## Scaffold Workflow

To create a new production-ready function:

```
[Step 1] Determine Type
  - API / Webhook / Scheduled / Background
  - HTTP methods needed (GET, POST, etc.)
  - Authentication required?

[Step 2] Generate Handler
  - Create file in netlify/functions/
  - Apply handler template (see Patterns below)
  - Add TypeScript types for request/response

[Step 3] Configure Routing
  - Add redirect in netlify.toml
  - Set allowed methods
  - Configure cache headers

[Step 4] Add Security
  - CORS configuration
  - Input validation
  - Auth middleware (if protected)
  - Environment variable checks

[Step 5] Register
  - Update .netlify-fn/registry.json (if exists)
  - Document the endpoint
```

## Patterns

### Pattern 1: Universal Handler
Reusable wrapper handling CORS, method checking, body parsing, and error responses. See `references/handler-patterns.md` for full implementation.

### Pattern 2: Webhook Handler
Signature-verified webhook receiver for Stripe, GitHub, Apple, Slack. See `references/handler-patterns.md`.

### Pattern 3: Scheduled Function (Cron)
Background tasks with `@netlify/functions` Config export. See `references/handler-patterns.md`.

### Pattern 4: Auth-Protected Endpoint
Token verification middleware for Supabase, Firebase, Auth0, Clerk, JWT. See `references/handler-patterns.md`.

### Error Codes
Consistent error response utility. See `references/handler-patterns.md`.

## Configuration
For netlify.toml routing, TypeScript setup, and environment variable management, see `references/configuration.md`.

## Self-Improvement

This skill learns project-specific patterns over time.

### First Run

1. Scan existing `netlify/functions/` for patterns
2. Detect shared utilities (handler, auth, errors)
3. Identify routing patterns from `netlify.toml`
4. Create `.netlify-fn/` directory with:
   - `registry.json`: inventory of all functions (name, type, route, auth requirement)
   - `patterns.json`: detected conventions (middleware stack, error codes, auth provider)

### Subsequent Runs

1. Read `.netlify-fn/patterns.json` to match project style
2. Scaffold new functions matching existing conventions
3. Update registry with new functions
4. Suggest shared middleware extraction when patterns repeat

### Pattern Recognition

If multiple functions share boilerplate, suggest extraction:

```
Detected: 4 functions manually checking auth headers
Suggestion: Extract to netlify/functions/lib/auth.ts

Detected: 3 functions with identical CORS setup
Suggestion: Use createHandler() wrapper from lib/handler.ts

Detected: Inconsistent error response format across functions
Suggestion: Adopt errorResponse() from lib/errors.ts
```

## Security Checklist

Before deploying any function:

- [ ] **Auth**: Protected endpoints verify tokens server-side (not just client-side)
- [ ] **Input validation**: All request bodies and query params validated before use
- [ ] **CORS**: Origin whitelist set — never use `*` for authenticated endpoints
- [ ] **Secrets**: API keys in environment variables, never hardcoded
- [ ] **Error messages**: No internal details (stack traces, SQL) leaked to clients
- [ ] **service_role**: Only used in server functions, never imported by client code
- [ ] **Webhook signatures**: All incoming webhooks verify sender identity
- [ ] **Rate limiting**: Public endpoints have request limits (via headers or middleware)
- [ ] **Logging**: Sensitive data (tokens, passwords, PII) never logged

## Constraints

### Required (MUST)

1. **Always handle CORS**: Every function must respond to OPTIONS preflight requests
2. **Always validate input**: Never trust client-provided data — validate shape and type
3. **Always use env vars for secrets**: Never hardcode API keys, tokens, or passwords
4. **Always return consistent JSON**: Same error format across all functions
5. **Always verify webhook signatures**: Never process unverified webhook payloads

### Prohibited (MUST NOT)

1. **Never expose service_role/secret keys to client**: Only use in server functions
2. **Never trust client auth claims without verification**: Always verify tokens server-side
3. **Never return stack traces to clients**: Log internally, return generic error messages
4. **Never use `*` CORS for authenticated endpoints**: Whitelist specific origins
5. **Never skip signature verification for webhooks**: Always verify the sender

## Best Practices

1. **One function per file**: Easier to maintain, deploy, and monitor
2. **Shared code in lib/**: Extract common utilities to `netlify/functions/lib/`
3. **TypeScript always**: Catch type errors at build time, not production
4. **Test locally first**: Use `netlify dev` before deploying to production
5. **Monitor logs**: Check Netlify dashboard → Functions → Logs after each deploy
6. **Minimize cold starts**: Fewer imports = faster startup. Lazy-load heavy dependencies
7. **Set timeouts**: Default is 10s (free) / 26s (paid). Design functions to complete within limits
8. **Idempotent webhooks**: External services may retry — handle duplicate events gracefully

## Bundled Resources

### References

- **`references/handler-patterns.md`**: Full implementation code for the createHandler wrapper, error response utility, webhook signature verification (Stripe, GitHub, generic HMAC), scheduled function (cron), and auth middleware by provider (Supabase, Firebase, Custom JWT). Copy-paste ready TypeScript.
- **`references/configuration.md`**: netlify.toml routing examples, TypeScript configuration, and environment variable management.

## References

- [Netlify Functions overview](https://docs.netlify.com/functions/overview/)
- [Netlify Functions v2 (Web API)](https://docs.netlify.com/functions/get-started/)
- [netlify.toml configuration](https://docs.netlify.com/configure-builds/file-based-configuration/)
- [Netlify CLI (local development)](https://docs.netlify.com/cli/get-started/)
- [Netlify scheduled functions](https://docs.netlify.com/functions/scheduled-functions/)
- [Netlify background functions](https://docs.netlify.com/functions/background-functions/)

## Related Skills

- `security-best-practices`: General web security patterns (complements function security)
- `supabase-automation`: Database operations often called from Netlify Functions
- `api-design`: REST API design principles for function endpoints
