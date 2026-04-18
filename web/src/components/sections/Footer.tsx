import Link from "next/link";

export default function Footer() {
  return (
    <footer className="border-t border-black/[0.06] py-10">
      <div className="mx-auto max-w-6xl px-6 flex flex-col md:flex-row items-start md:items-center justify-between gap-6 text-sm text-mute">
        <div className="flex items-center gap-2.5">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/icon.png" alt="" width={22} height={22} className="rounded-[5px]" />
          <span className="text-ink-soft">Scratchpad</span>
          <span>·</span>
          <span>MIT licensed.</span>
        </div>
        <nav className="flex items-center gap-5">
          <Link href="https://github.com/KrishKrosh/Scratchpad" className="hover:text-ink">GitHub</Link>
          <Link href="https://github.com/KrishKrosh/Scratchpad/releases" className="hover:text-ink">Releases</Link>
          <Link href="https://github.com/KrishKrosh/Scratchpad/issues" className="hover:text-ink">Issues</Link>
        </nav>
      </div>
    </footer>
  );
}
