import Link from "next/link";

/**
 * The primary CTA. Points at a public download link that you can swap
 * in later — for now it falls back to the GitHub releases page.
 */
export default function DownloadButton({
  href = "/download",
  label = "Download for macOS",
}: {
  href?: string;
  label?: string;
}) {
  return (
    <Link
      href={href}
      className="group relative inline-flex items-center gap-2.5 h-12 pl-5 pr-6 rounded-full bg-ink text-paper hover:bg-indigo transition-colors"
    >
      <AppleGlyph />
      <span className="font-medium">{label}</span>
      <span className="ml-1 text-paper/70 text-sm">· Apple silicon</span>
    </Link>
  );
}

function AppleGlyph() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 18" fill="currentColor">
      <path d="M10.54 9.56c-.02-2.02 1.65-2.99 1.72-3.04-.94-1.37-2.4-1.56-2.92-1.58-1.24-.13-2.43.73-3.06.73-.63 0-1.61-.71-2.64-.69-1.36.02-2.61.79-3.31 2-1.41 2.44-.36 6.06 1.02 8.04.68.97 1.48 2.05 2.52 2.01 1.01-.04 1.39-.65 2.61-.65 1.22 0 1.56.65 2.63.63 1.09-.02 1.78-.98 2.44-1.96.77-1.12 1.09-2.22 1.11-2.28-.03-.01-2.13-.82-2.16-3.25ZM8.7 3.54c.55-.67.93-1.61.82-2.54-.8.03-1.77.54-2.34 1.21-.51.6-.96 1.55-.83 2.47.89.07 1.8-.45 2.35-1.14Z" />
    </svg>
  );
}
