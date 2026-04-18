// Tiny health check — also the template for future API routes that this
// site might back (release feed, webhook receiver, etc.).
export const dynamic = "force-static";

export function GET() {
  return Response.json({ ok: true, name: "scratchpad-web" });
}
