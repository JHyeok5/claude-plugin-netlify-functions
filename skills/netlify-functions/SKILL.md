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

### Pattern 1: Reusable Handler Wrapper

A shared utility that handles CORS, method checking, error handling, and response formatting. Create once, use in every function.

```typescript
// netlify/functions/lib/handler.ts

type HttpMethod = "GET" | "POST" | "PUT" | "DELETE" | "PATCH";

interface HandlerOptions {
  allowedMethods?: HttpMethod[];
  allowedOrigins?: string[];
  requireAuth?: boolean;
}

interface HandlerContext {
  req: Request;
  body: unknown;
  headers: Headers;
  params: URLSearchParams;
  userId?: string;
}

export function createHandler(
  options: HandlerOptions,
  handler: (ctx: HandlerContext) => Promise<Response>
) {
  return async (req: Request) => {
    // --- CORS ---
    const origin = req.headers.get("origin") || "";
    const allowed = options.allowedOrigins || ["*"];
    const corsOrigin = allowed.includes("*")
      ? "*"
      : allowed.includes(origin) ? origin : "";

    const corsHeaders: Record<string, string> = {
      "Access-Control-Allow-Origin": corsOrigin,
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Access-Control-Allow-Methods": (options.allowedMethods || ["GET"]).join(", "),
    };

    // Preflight
    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    // --- Method check ---
    const methods = options.allowedMethods || ["GET"];
    if (!methods.includes(req.method as HttpMethod)) {
      return Response.json(
        { error: `Method ${req.method} not allowed`, code: "METHOD_NOT_ALLOWED" },
        { status: 405, headers: corsHeaders }
      );
    }

    try {
      // --- Parse body ---
      let body: unknown = null;
      if (["POST", "PUT", "PATCH"].includes(req.method)) {
        try { body = await req.json(); } catch { body = null; }
      }

      const ctx: HandlerContext = {
        req,
        body,
        headers: req.headers,
        params: new URL(req.url).searchParams,
      };

      // --- Execute handler ---
      const response = await handler(ctx);

      // Add CORS to response
      const newHeaders = new Headers(response.headers);
      for (const [k, v] of Object.entries(corsHeaders)) newHeaders.set(k, v);

      return new Response(response.body, {
        status: response.status,
        headers: newHeaders,
      });
    } catch (error) {
      console.error("[function error]", error);
      return Response.json(
        { error: "Internal server error", code: "INTERNAL_ERROR" },
        { status: 500, headers: corsHeaders }
      );
    }
  };
}
```

**Usage:**

```typescript
// netlify/functions/users.ts
import { createHandler } from "./lib/handler";

export default createHandler(
  { allowedMethods: ["GET", "POST"], allowedOrigins: ["https://mysite.com"] },
  async (ctx) => {
    if (ctx.req.method === "GET") {
      const users = await db.getUsers();
      return Response.json(users);
    }

    // POST
    const { name, email } = ctx.body as { name: string; email: string };
    if (!name || !email) {
      return Response.json(
        { error: "name and email are required", code: "MISSING_FIELD" },
        { status: 400 }
      );
    }

    const user = await db.createUser({ name, email });
    return Response.json(user, { status: 201 });
  }
);
```

### Pattern 2: Webhook Handler

For receiving webhooks from external services. Key difference: verify the sender's signature before processing.

```typescript
// netlify/functions/stripe-webhook.ts
import Stripe from "stripe";

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);

export default async (req: Request) => {
  // 1. Only accept POST
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  // 2. Verify webhook signature (CRITICAL — never skip this)
  const signature = req.headers.get("stripe-signature");
  if (!signature) {
    return Response.json({ error: "Missing signature" }, { status: 401 });
  }

  const rawBody = await req.text();
  let event: Stripe.Event;

  try {
    event = stripe.webhooks.constructEvent(
      rawBody,
      signature,
      process.env.STRIPE_WEBHOOK_SECRET!
    );
  } catch {
    return Response.json({ error: "Invalid signature" }, { status: 401 });
  }

  // 3. Handle event types
  switch (event.type) {
    case "checkout.session.completed":
      await handlePaymentSuccess(event.data.object);
      break;
    case "customer.subscription.deleted":
      await handleCancellation(event.data.object);
      break;
    default:
      console.log(`Unhandled event: ${event.type}`);
  }

  // 4. Always return 200 to acknowledge receipt
  return Response.json({ received: true });
};
```

**Webhook signature verification by provider:**

| Provider | Header | Library |
|----------|--------|---------|
| Stripe | `stripe-signature` | `stripe.webhooks.constructEvent()` |
| GitHub | `x-hub-signature-256` | HMAC SHA-256 verification |
| Apple | JWS in body | X.509 certificate chain validation |
| Slack | `x-slack-signature` | HMAC SHA-256 with timestamp |
| Twilio | `x-twilio-signature` | HMAC SHA-1 verification |

### Pattern 3: Scheduled Function (Cron)

```typescript
// netlify/functions/daily-cleanup.ts
import { Config } from "@netlify/functions";

export default async () => {
  console.log("Running daily cleanup...");

  try {
    const result = await performCleanup();
    console.log(`Cleanup complete: ${result.deleted} records removed`);
  } catch (error) {
    // Log but don't throw — no client to receive the error
    console.error("Cleanup failed:", error);
  }
};

// Cron expression: minute hour day month weekday
export const config: Config = {
  schedule: "0 3 * * *", // Daily at 3:00 AM UTC
};
```

**Common cron schedules:**

| Schedule | Expression | Use Case |
|----------|-----------|----------|
| Every hour | `0 * * * *` | Cache refresh |
| Daily 3 AM | `0 3 * * *` | Cleanup, reports |
| Weekly Monday | `0 9 * * 1` | Weekly digest |
| Every 5 min | `*/5 * * * *` | Health check (use sparingly) |

### Pattern 4: Auth-Protected Endpoint

```typescript
// netlify/functions/lib/auth.ts
import { createClient } from "@supabase/supabase-js";

// Use service_role key for server-side operations (bypasses RLS)
const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);

export async function verifyAuth(
  headers: Headers
): Promise<{ userId: string } | null> {
  const token = headers.get("authorization")?.replace("Bearer ", "");
  if (!token) return null;

  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user) return null;

  return { userId: user.id };
}
```

**Usage in a function:**

```typescript
// netlify/functions/my-data.ts
import { createHandler } from "./lib/handler";
import { verifyAuth } from "./lib/auth";

export default createHandler(
  { allowedMethods: ["GET"] },
  async (ctx) => {
    const auth = await verifyAuth(ctx.headers);
    if (!auth) {
      return Response.json({ error: "Unauthorized" }, { status: 401 });
    }

    const data = await getDataForUser(auth.userId);
    return Response.json(data);
  }
);
```

**Auth verification methods by provider:**

| Auth Provider | Verification | Server Key |
|---------------|-------------|------------|
| Supabase | `supabase.auth.getUser(token)` | `SUPABASE_SERVICE_ROLE_KEY` |
| Firebase | `admin.auth().verifyIdToken(token)` | Service account JSON |
| Auth0 | `jwks-rsa` + `jsonwebtoken` | JWKS endpoint |
| Clerk | `clerkClient.verifyToken(token)` | `CLERK_SECRET_KEY` |
| Custom JWT | `jsonwebtoken.verify(token, secret)` | `JWT_SECRET` |

## Error Code Pattern

Consistent error responses across all functions:

```typescript
// netlify/functions/lib/errors.ts
const ERROR_CODES = {
  // Auth
  UNAUTHORIZED:        { status: 401, message: "Authentication required" },
  FORBIDDEN:           { status: 403, message: "Insufficient permissions" },

  // Validation
  INVALID_INPUT:       { status: 400, message: "Invalid input" },
  MISSING_FIELD:       { status: 400, message: "Required field missing" },

  // Resources
  NOT_FOUND:           { status: 404, message: "Resource not found" },
  CONFLICT:            { status: 409, message: "Resource already exists" },

  // Rate limiting
  RATE_LIMITED:        { status: 429, message: "Too many requests, try again later" },

  // Server
  INTERNAL_ERROR:      { status: 500, message: "Internal server error" },
  SERVICE_UNAVAILABLE: { status: 503, message: "Service temporarily unavailable" },
} as const;

type ErrorCode = keyof typeof ERROR_CODES;

export function errorResponse(code: ErrorCode, details?: string) {
  const { status, message } = ERROR_CODES[code];
  return Response.json(
    { error: message, code, ...(details && { details }) },
    { status }
  );
}
```

**Usage:**

```typescript
import { errorResponse } from "./lib/errors";

if (!email) return errorResponse("MISSING_FIELD", "email is required");
if (!user)  return errorResponse("NOT_FOUND", `User ${id} not found`);
if (exists) return errorResponse("CONFLICT", "Email already registered");
```

## Configuration

### netlify.toml Routing

```toml
# Option A: Catch-all (simple)
[[redirects]]
  from = "/api/*"
  to = "/.netlify/functions/:splat"
  status = 200

# Option B: Explicit routes (more control, recommended for production)
[[redirects]]
  from = "/api/users"
  to = "/.netlify/functions/users"
  status = 200

[[redirects]]
  from = "/api/users/:id"
  to = "/.netlify/functions/users-by-id"
  status = 200

# Webhooks (external services — no auth redirect)
[[redirects]]
  from = "/webhooks/stripe"
  to = "/.netlify/functions/stripe-webhook"
  status = 200

# Cache headers for public API
[[headers]]
  for = "/api/public/*"
  [headers.values]
    Cache-Control = "public, max-age=3600"
```

### TypeScript Configuration

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "outDir": "./dist",
    "rootDir": "."
  },
  "include": ["./**/*.ts"],
  "exclude": ["node_modules", "dist"]
}
```

### Environment Variables

Set in Netlify dashboard: **Site Settings → Environment Variables**

```bash
# Database (example: Supabase)
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...    # server-side only, never expose to client

# External services
STRIPE_SECRET_KEY=sk_...
STRIPE_WEBHOOK_SECRET=whsec_...

# App
SITE_URL=https://mysite.com
```

**Rule**: `SERVICE_ROLE_KEY` and `SECRET_KEY` are server-only. The client must never see them. Netlify Functions run server-side, so these are safe here.

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

- **`references/handler-patterns.md`**: Full implementation code for the createHandler wrapper, error response utility, webhook signature verification (Stripe, GitHub, generic HMAC), and auth middleware by provider (Supabase, Firebase, Custom JWT). Copy-paste ready TypeScript.

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
