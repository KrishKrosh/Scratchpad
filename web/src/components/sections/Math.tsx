import AppWindow from "../AppWindow";
import { SectionEyebrow, SectionTitle } from "./Tools";

export default function MathSection() {
  return (
    <section id="math" className="py-24 md:py-32">
      <div className="mx-auto max-w-6xl px-6 grid md:grid-cols-[1.1fr_1fr] gap-16 md:gap-24 items-center">
        <MathMock />

        <div>
          <SectionEyebrow>Handwriting → LaTeX</SectionEyebrow>
          <SectionTitle>
            Scribble the math.{" "}
            <span className="font-serif italic font-normal text-indigo">
              Get the LaTeX.
            </span>
          </SectionTitle>
          <p className="mt-5 text-lg text-ink-soft/85 max-w-lg">
            A small MLX model runs on your Mac&apos;s neural engine — so your
            notebook never leaves your laptop. Select the ink, hit convert,
            paste into your doc. That&apos;s the whole loop.
          </p>

          <div className="mt-8 inline-flex items-center gap-2.5 rounded-full border border-black/10 px-4 py-2 text-sm">
            <span className="inline-block h-1.5 w-1.5 rounded-full bg-tool-green" />
            Runs locally · No cloud · No account
          </div>
        </div>
      </div>
    </section>
  );
}

/**
 * A two-layer mock: top half is the "scribbled" equation using an italic
 * serif (reads like handwriting without trying to fake ink); bottom is
 * the clean LaTeX output the model returns.
 */
function MathMock() {
  return (
    <div className="relative" data-ink="#513DEF">
      <AppWindow title="derivations.scratchpad">
        <div className="relative h-[440px] bg-paper dot-grid dot-grid-fade px-10 pt-12 pb-10 flex flex-col">
          {/* Scribbled input */}
          <div className="relative flex-1 flex items-center justify-center">
            {/* Selection rectangle */}
            <div className="absolute inset-x-10 top-4 bottom-10 rounded-md border border-dashed border-tool-blue/70 pointer-events-none" />
            <div
              className="font-serif italic text-indigo leading-none select-none"
              style={{
                fontSize: "72px",
                transform: "rotate(-1.5deg) translateY(-6px)",
                textShadow: "0 0.5px 0 rgba(81,61,239,0.15)",
                letterSpacing: "0.01em",
              }}
            >
              e
              <sup
                className="font-serif italic"
                style={{ fontSize: "0.5em", marginLeft: "0.02em", top: "-0.55em", position: "relative" }}
              >
                iπ
              </sup>
              <span style={{ margin: "0 0.18em" }}>+</span>1
              <span style={{ margin: "0 0.18em" }}>=</span>0
            </div>

            {/* Convert chip sits over the canvas */}
            <div className="absolute left-0 bottom-2 glass rounded-full px-3.5 py-1.5 text-xs font-medium flex items-center gap-2">
              <span className="inline-block h-2 w-2 rounded-full bg-indigo" />
              Convert to LaTeX
              <span className="text-mute">· ⌥⌘L</span>
            </div>
          </div>

          {/* LaTeX output row */}
          <div className="relative rounded-xl bg-white border border-black/[0.06] p-4 flex items-center gap-4">
            <div className="text-mute text-[10px] uppercase tracking-[0.18em] shrink-0">
              output
            </div>
            <code className="font-mono text-[13px] text-ink-soft/90 truncate">
              {"e^{i\\pi} + 1 = 0"}
            </code>
            <button className="ml-auto inline-flex items-center gap-1.5 text-xs text-mute hover:text-ink">
              <CopyGlyph /> Copy
            </button>
          </div>
        </div>
      </AppWindow>
    </div>
  );
}

function CopyGlyph() {
  return (
    <svg width="12" height="12" viewBox="0 0 16 16" fill="none">
      <rect x="4" y="4" width="9" height="10" rx="1.5" stroke="currentColor" strokeWidth="1.3" />
      <path d="M3 12 V3 a1 1 0 0 1 1 -1 h7" stroke="currentColor" strokeWidth="1.3" fill="none" />
    </svg>
  );
}
