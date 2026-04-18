# scratchpad-web

Landing page for [Scratchpad](../) — single page, Next.js 16 + Tailwind v4,
deployable to Vercel. Also the home for any HTTP APIs the desktop app
might need later (release manifests, webhook receivers, etc.).

## Local dev

```bash
pnpm install
pnpm dev        # http://localhost:3000
```

## Deploy

The repo root for this site is `web/` — point Vercel at it.

```bash
# one-time
pnpm dlx vercel link
# ship
pnpm dlx vercel --prod
```

Set `NEXT_PUBLIC_SITE_URL` in the Vercel project to the production URL so
OpenGraph / Twitter image paths resolve correctly (falls back to
`https://scratchpad.app`).

## Structure

- `src/app/layout.tsx` — fonts (Geist + Instrument Serif), metadata, mounts the marker cursor
- `src/app/page.tsx` — section composition
- `src/app/globals.css` — theme tokens, dot-grid, glass, ink animations
- `src/components/MarkerCursor.tsx` — canvas-backed ink-trail cursor
- `src/components/AppWindow.tsx` — macOS window chrome
- `src/components/FloatingToolbar.tsx` — in-app floating toolbar replica
- `src/components/HeroCanvas.tsx` — hero product shot with animating strokes
- `src/components/sections/*` — each landing section
- `src/app/api/health/route.ts` — example route handler (swap for real APIs)

## Adding an API route

Drop a `route.ts` into `src/app/api/<name>/`. See `api/health/route.ts`
for the shape. Default runtime is Node; mark `export const runtime = "edge"`
if you want Edge.

## Notes

- No shadcn / no component library — the page is small enough that
  bespoke SVGs and Tailwind utilities keep it lean.
- The marker cursor is disabled on coarse pointers (touch), which
  returns the native cursor on mobile automatically.
- Product screenshots are rendered in-page as SVG/HTML so they stay
  pixel-crisp at any resolution. If you want rasterized assets (App
  Store listing, social cards), see `adamlyttleapps/claude-skill-aso-appstore-screenshots` — that skill targets iOS but its benefit-discovery workflow is a good template.
