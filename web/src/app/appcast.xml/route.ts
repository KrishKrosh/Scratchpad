import { NextResponse } from "next/server";

/**
 * Appcast feed for Sparkle. We stay out of the content-generation business:
 * CI attaches `appcast.xml` to each GitHub release (built with Sparkle's
 * `generate_appcast` tool, which signs items with our EdDSA private key).
 * This route just proxies the latest release's appcast asset, so the feed
 * URL baked into the shipped app (`SUFeedURL`) is stable across releases.
 *
 * Rationale for proxying instead of redirecting:
 *   - Sparkle follows redirects, but a single stable URL is easier to cache
 *   - We can rewrite enclosure URLs later if we ever move DMG hosting
 */

export const runtime = "edge";
// Recheck at most every 5 minutes — Sparkle's default check interval is
// daily, so this is comfortably fresh.
export const revalidate = 300;

const OWNER = process.env.GITHUB_RELEASE_OWNER ?? "KrishKrosh";
const REPO = process.env.GITHUB_RELEASE_REPO ?? "Scratchpad";

export async function GET() {
  try {
    const release = await fetchLatestRelease();
    if (!release) return emptyFeed("no releases yet");

    const appcastAsset = release.assets.find(
      (a) => a.name === "appcast.xml",
    );
    if (!appcastAsset) {
      // CI hasn't attached an appcast yet — fall back to an empty channel so
      // Sparkle doesn't error, it'll just see "no updates available".
      return emptyFeed(`release ${release.tag_name} has no appcast.xml asset`);
    }

    const res = await fetch(appcastAsset.browser_download_url, {
      // GitHub asset URLs 302 to a signed S3 link; let edge follow it.
      redirect: "follow",
      next: { revalidate: 300 },
    });
    if (!res.ok) return emptyFeed(`upstream ${res.status}`);

    const xml = await res.text();
    return new NextResponse(xml, {
      status: 200,
      headers: {
        "Content-Type": "application/rss+xml; charset=utf-8",
        // Cache at the edge for 5m, allow 1h of stale-while-revalidate.
        "Cache-Control":
          "public, max-age=60, s-maxage=300, stale-while-revalidate=3600",
      },
    });
  } catch (err) {
    return emptyFeed(`error: ${(err as Error).message}`);
  }
}

type Release = {
  tag_name: string;
  assets: { name: string; browser_download_url: string }[];
};

async function fetchLatestRelease(): Promise<Release | null> {
  const headers: HeadersInit = { Accept: "application/vnd.github+json" };
  if (process.env.GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }
  const r = await fetch(
    `https://api.github.com/repos/${OWNER}/${REPO}/releases/latest`,
    { headers, next: { revalidate: 300 } },
  );
  if (r.status === 404) return null;
  if (!r.ok) throw new Error(`github ${r.status}`);
  return (await r.json()) as Release;
}

function emptyFeed(note: string) {
  const xml = `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Scratchpad</title>
    <link>https://scratchpad.app/appcast.xml</link>
    <description>${escapeXml(note)}</description>
  </channel>
</rss>`;
  return new NextResponse(xml, {
    status: 200,
    headers: {
      "Content-Type": "application/rss+xml; charset=utf-8",
      "Cache-Control": "public, max-age=60, s-maxage=60",
    },
  });
}

function escapeXml(s: string) {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}
