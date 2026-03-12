# Handler Patterns Reference

Production-ready code templates for Netlify Functions.

## Complete Handler Wrapper (TypeScript)

Full implementation of `createHandler` with all features:

```typescript
// netlify/functions/lib/handler.ts

type HttpMethod = "GET" | "POST" | "PUT" | "DELETE" | "PATCH";

interface HandlerOptions {
  allowedMethods?: HttpMethod[];
  allowedOrigins?: string[];
  requireAuth?: boolean;
  rateLimit?: {
    windowMs: number;
    max: number;
  };
}

interface HandlerContext {
  req: Request;
  body: unknown;
  headers: Headers;
  params: URLSearchParams;
  userId?: string;
}

type HandlerFn = (ctx: HandlerContext) => Promise<Response>;

export function createHandler(options: HandlerOptions, handler: HandlerFn) {
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

    // Method check
    const methods = options.allowedMethods || ["GET"];
    if (!methods.includes(req.method as HttpMethod)) {
      return Response.json(
        { error: `Method ${req.method} not allowed`, code: "METHOD_NOT_ALLOWED" },
        { status: 405, headers: corsHeaders }
      );
    }

    // No CORS origin match (not a preflight, but origin doesn't match)
    if (corsOrigin === "" && !allowed.includes("*") && origin) {
      return Response.json(
        { error: "Origin not allowed", code: "CORS_REJECTED" },
        { status: 403, headers: corsHeaders }
      );
    }

    try {
      // Parse body
      let body: unknown = null;
      if (["POST", "PUT", "PATCH"].includes(req.method)) {
        const contentType = req.headers.get("content-type") || "";
        if (contentType.includes("application/json")) {
          try { body = await req.json(); } catch { body = null; }
        } else if (contentType.includes("application/x-www-form-urlencoded")) {
          const text = await req.text();
          body = Object.fromEntries(new URLSearchParams(text));
        }
      }

      const ctx: HandlerContext = {
        req,
        body,
        headers: req.headers,
        params: new URL(req.url).searchParams,
      };

      const response = await handler(ctx);

      // Add CORS headers
      const newHeaders = new Headers(response.headers);
      for (const [k, v] of Object.entries(corsHeaders)) {
        newHeaders.set(k, v);
      }

      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: newHeaders,
      });
    } catch (error) {
      console.error("[function error]", error instanceof Error ? error.message : error);
      return Response.json(
        { error: "Internal server error", code: "INTERNAL_ERROR" },
        { status: 500, headers: corsHeaders }
      );
    }
  };
}
```

## Error Response Utility

```typescript
// netlify/functions/lib/errors.ts

const ERROR_CODES = {
  UNAUTHORIZED:        { status: 401, message: "Authentication required" },
  FORBIDDEN:           { status: 403, message: "Insufficient permissions" },
  INVALID_INPUT:       { status: 400, message: "Invalid input" },
  MISSING_FIELD:       { status: 400, message: "Required field missing" },
  NOT_FOUND:           { status: 404, message: "Resource not found" },
  CONFLICT:            { status: 409, message: "Resource already exists" },
  RATE_LIMITED:        { status: 429, message: "Too many requests" },
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

## Webhook Signature Verification

### Stripe

```typescript
import Stripe from "stripe";

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);

async function verifyStripeWebhook(req: Request): Promise<Stripe.Event> {
  const signature = req.headers.get("stripe-signature");
  if (!signature) throw new Error("Missing stripe-signature header");

  const rawBody = await req.text();
  return stripe.webhooks.constructEvent(
    rawBody,
    signature,
    process.env.STRIPE_WEBHOOK_SECRET!
  );
}
```

### GitHub

```typescript
import { createHmac, timingSafeEqual } from "crypto";

async function verifyGitHubWebhook(req: Request): Promise<boolean> {
  const signature = req.headers.get("x-hub-signature-256");
  if (!signature) return false;

  const rawBody = await req.text();
  const expected = "sha256=" + createHmac("sha256", process.env.GITHUB_WEBHOOK_SECRET!)
    .update(rawBody)
    .digest("hex");

  return timingSafeEqual(Buffer.from(signature), Buffer.from(expected));
}
```

### Generic HMAC

```typescript
import { createHmac, timingSafeEqual } from "crypto";

function verifyHmacSignature(
  payload: string,
  signature: string,
  secret: string,
  algorithm: "sha256" | "sha1" = "sha256",
  prefix: string = ""
): boolean {
  const expected = prefix + createHmac(algorithm, secret)
    .update(payload)
    .digest("hex");

  return timingSafeEqual(
    Buffer.from(signature),
    Buffer.from(expected)
  );
}
```

## Auth Middleware by Provider

### Supabase

```typescript
import { createClient } from "@supabase/supabase-js";

const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);

export async function verifyAuth(headers: Headers) {
  const token = headers.get("authorization")?.replace("Bearer ", "");
  if (!token) return null;

  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user) return null;

  return { userId: user.id, email: user.email };
}
```

### Firebase Admin

```typescript
import { initializeApp, cert } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";

const app = initializeApp({
  credential: cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT!)),
});

export async function verifyAuth(headers: Headers) {
  const token = headers.get("authorization")?.replace("Bearer ", "");
  if (!token) return null;

  try {
    const decoded = await getAuth(app).verifyIdToken(token);
    return { userId: decoded.uid, email: decoded.email };
  } catch {
    return null;
  }
}
```

### Custom JWT

```typescript
import jwt from "jsonwebtoken";

export function verifyAuth(headers: Headers) {
  const token = headers.get("authorization")?.replace("Bearer ", "");
  if (!token) return null;

  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET!) as { userId: string };
    return { userId: payload.userId };
  } catch {
    return null;
  }
}
```

## Scheduled Function (Cron)

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
