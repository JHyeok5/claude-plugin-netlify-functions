# Configuration Reference

## netlify.toml Routing

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

## TypeScript Configuration

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

## Environment Variables

Set in Netlify dashboard: **Site Settings > Environment Variables**

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
