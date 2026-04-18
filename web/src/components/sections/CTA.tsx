import DownloadButton from "../DownloadButton";
import Link from "next/link";

export default function CTA() {
  return (
    <section className="relative py-28 md:py-36 overflow-hidden">
      {/* Dotted wash */}
      <div className="absolute inset-0 dot-grid dot-grid-fade opacity-90" />

      {/* Decorative scribbles */}
      <svg
        viewBox="0 0 1200 400"
        className="absolute inset-0 w-full h-full pointer-events-none"
        aria-hidden
      >
        <path
          d="M80 320 C 200 260, 300 360, 420 300"
          stroke="#513DEF"
          strokeWidth="3"
          strokeLinecap="round"
          fill="none"
          opacity="0.5"
          className="ink-stroke"
          style={{ ["--len" as string]: 500, ["--delay" as string]: "0s" } as React.CSSProperties}
        />
        <path
          d="M780 110 c 40 -40, 120 -10, 160 30 s 80 120, 180 60"
          stroke="#E53A5B"
          strokeWidth="3"
          strokeLinecap="round"
          fill="none"
          opacity="0.45"
          className="ink-stroke"
          style={{ ["--len" as string]: 600, ["--delay" as string]: "0.3s" } as React.CSSProperties}
        />
      </svg>

      <div className="relative mx-auto max-w-3xl px-6 text-center">
        <h2 className="text-4xl md:text-6xl leading-[1.05] tracking-[-0.02em] font-semibold">
          Put the thought{" "}
          <span className="font-serif italic font-normal text-indigo scribble-underline">
            somewhere.
          </span>
        </h2>
        <p className="mt-6 text-lg md:text-xl text-ink-soft/85">
          Free, offline, open-source, and about the size of three web
          pages. For Apple silicon Macs, running macOS 14 or later.
        </p>

        <div className="mt-10 flex flex-wrap items-center justify-center gap-3">
          <DownloadButton />
          <Link
            href="https://github.com/KrishKrosh/Scratchpad"
            className="inline-flex items-center gap-2 h-12 px-5 rounded-full border border-black/10 text-ink hover:bg-black/[0.03] transition"
          >
            Star on GitHub
          </Link>
        </div>
      </div>
    </section>
  );
}
