import HeroCanvas from "../HeroCanvas";
import DownloadButton from "../DownloadButton";
import Link from "next/link";

export default function Hero() {
  return (
    <section className="relative pt-10 md:pt-16 pb-28 md:pb-40">
      {/* Dotted paper wash behind the whole hero */}
      <div className="pointer-events-none absolute inset-x-0 top-0 h-[780px] dot-grid dot-grid-fade opacity-80" />

      <div className="relative mx-auto max-w-6xl px-6">
        {/* Tiny brand row */}
        <div className="flex items-center justify-between mb-12">
          <div className="flex items-center gap-2.5">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/icon.png" alt="" width={28} height={28} className="rounded-[7px]" />
            <span className="font-medium tracking-tight">Scratchpad</span>
            <span className="ml-2 text-[11px] uppercase tracking-[0.14em] text-mute">
              for macOS
            </span>
          </div>
          <nav className="hidden md:flex items-center gap-7 text-sm text-ink-soft/80">
            <a href="#tools" className="hover:text-ink">Tools</a>
            <a href="#trackpad" className="hover:text-ink">Trackpad</a>
            <a href="#math" className="hover:text-ink">Math</a>
            <a href="#library" className="hover:text-ink">Library</a>
            <Link
              href="https://github.com/KrishKrosh/Scratchpad"
              className="hover:text-ink"
            >
              GitHub
            </Link>
          </nav>
        </div>

        {/* Headline */}
        <div className="max-w-3xl">
          <p className="text-[13px] uppercase tracking-[0.22em] text-indigo mb-5">
            A quiet place to think
          </p>
          <h1 className="font-sans text-[44px] md:text-[68px] leading-[1.02] tracking-[-0.02em] font-semibold text-ink">
            Think{" "}
            <span className="font-serif italic font-normal text-indigo">
              on
            </span>{" "}
            your trackpad.
          </h1>
          <p className="mt-6 max-w-xl text-lg md:text-xl leading-relaxed text-ink-soft/90">
            Scratchpad turns the trackpad surface into a pressure-sensitive
            drawing canvas. Sketch a diagram, scribble an equation that
            converts to LaTeX, stash it in a library that stays out of your
            way.
          </p>

          <div className="mt-9 flex flex-wrap items-center gap-3">
            <DownloadButton />
            <Link
              href="https://github.com/KrishKrosh/Scratchpad"
              className="inline-flex items-center gap-2 h-12 px-5 rounded-full border border-black/10 text-ink hover:bg-black/[0.03] transition"
            >
              <GithubGlyph /> View on GitHub
            </Link>
            <span className="ml-1 text-sm text-mute">Free · open source</span>
          </div>
        </div>

        {/* Product shot */}
        <div className="mt-20 md:mt-24 relative">
          <HeroCanvas />
        </div>
      </div>
    </section>
  );
}

function GithubGlyph() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
      <path d="M8 0C3.58 0 0 3.67 0 8.2a8.22 8.22 0 0 0 5.47 7.79c.4.07.55-.18.55-.4 0-.2-.01-.73-.01-1.43-2.22.5-2.69-1.1-2.69-1.1-.36-.94-.89-1.2-.89-1.2-.73-.5.05-.5.05-.5.81.06 1.23.84 1.23.84.72 1.25 1.88.89 2.34.68.07-.54.28-.9.5-1.1-1.77-.2-3.63-.91-3.63-4.04 0-.89.31-1.62.82-2.19-.08-.2-.36-1.03.08-2.16 0 0 .67-.22 2.2.84a7.48 7.48 0 0 1 4 0c1.53-1.06 2.2-.84 2.2-.84.44 1.13.16 1.96.08 2.16.51.57.82 1.3.82 2.19 0 3.14-1.87 3.83-3.65 4.03.29.26.54.76.54 1.53 0 1.11-.01 2-.01 2.27 0 .22.15.48.55.4A8.22 8.22 0 0 0 16 8.2C16 3.67 12.42 0 8 0Z" />
    </svg>
  );
}
