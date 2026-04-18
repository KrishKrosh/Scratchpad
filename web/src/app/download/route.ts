import { NextResponse } from "next/server";

/**
 * `/download` → 302 to the latest Scratchpad DMG.
 *
 * The landing page's Download CTA points here so the button "just works"
 * the moment CI publishes a release — no marketing-site redeploy needed.
 * Falls through to the releases page if we can't resolve an asset.
 */

export const runtime = "edge";
export const dynamic = "force-dynamic";

const OWNER = process.env.GITHUB_RELEASE_OWNER ?? "KrishKrosh";
const REPO = process.env.GITHUB_RELEASE_REPO ?? "Scratchpad";
const RELEASES_PAGE = `https://github.com/${OWNER}/${REPO}/releases/latest`;

export async function GET() {
  try {
    const headers: HeadersInit = { Accept: "application/vnd.github+json" };
    if (process.env.GITHUB_TOKEN) {
      headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
    }
    const res = await fetch(
      `https://api.github.com/repos/${OWNER}/${REPO}/releases/latest`,
      { headers, cache: "no-store" },
    );
    if (!res.ok) return NextResponse.redirect(RELEASES_PAGE, 302);

    const release = (await res.json()) as {
      assets: { name: string; browser_download_url: string }[];
    };
    // Prefer a .dmg; any one will do — CI only attaches the one.
    const dmg = release.assets.find((a) => a.name.endsWith(".dmg"));
    return NextResponse.redirect(dmg?.browser_download_url ?? RELEASES_PAGE, 302);
  } catch {
    return NextResponse.redirect(RELEASES_PAGE, 302);
  }
}
