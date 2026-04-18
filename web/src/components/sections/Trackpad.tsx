import { SectionEyebrow, SectionTitle } from "./Tools";

export default function Trackpad() {
  return (
    <section id="trackpad" className="py-24 md:py-32 bg-white/60 border-y border-black/[0.05]">
      <div className="mx-auto max-w-6xl px-6 grid md:grid-cols-2 gap-14 md:gap-20 items-center">
        <div>
          <SectionEyebrow>Trackpad-first</SectionEyebrow>
          <SectionTitle>
            The surface{" "}
            <span className="font-serif italic font-normal">
              you already touch.
            </span>
          </SectionTitle>
          <p className="mt-5 text-lg text-ink-soft/85 max-w-lg">
            Press ⌘D and your trackpad becomes a pressure-sensitive canvas.
            Palm rejection handles errant contacts. Two fingers? That&apos;s undo.
            Keep your hand where it&apos;s been all day.
          </p>

          <ul className="mt-8 space-y-3.5 text-ink-soft/90">
            <Bullet>Force-touch mapped to stroke weight.</Bullet>
            <Bullet>Cursor hides while you draw, returns when you stop.</Bullet>
            <Bullet>Works with any Apple Magic Trackpad or built-in.</Bullet>
          </ul>
        </div>

        <TrackpadMock />
      </div>
    </section>
  );
}

function Bullet({ children }: { children: React.ReactNode }) {
  return (
    <li className="flex gap-3">
      <span className="mt-[10px] h-1.5 w-1.5 rounded-full bg-indigo shrink-0" />
      <span>{children}</span>
    </li>
  );
}

function TrackpadMock() {
  // A slightly tilted trackpad with a finger-drawn indigo squiggle on top,
  // and a pressure meter in the corner.
  return (
    <div className="relative aspect-[5/4]">
      <div
        className="absolute inset-0 rounded-[36px] bg-[linear-gradient(155deg,#eceae2_0%,#dad7cc_55%,#c2bfb2_100%)] shadow-[0_30px_60px_-20px_rgba(0,0,0,0.35),0_8px_16px_-6px_rgba(0,0,0,0.25)] press"
        style={{ transform: "perspective(1200px) rotateX(10deg) rotateY(-6deg)" }}
      >
        {/* Inner trackpad bevel */}
        <div className="absolute inset-[14px] rounded-[28px] bg-[linear-gradient(155deg,#f4f2ec,#e3e0d6)] shadow-[inset_0_2px_3px_rgba(255,255,255,0.8),inset_0_-1px_2px_rgba(0,0,0,0.08)] overflow-hidden">
            <svg viewBox="0 0 500 400" className="absolute inset-0 w-full h-full">
              {/* Squiggle drawn with variable width */}
              <path
                d="M70 270 C 130 100, 230 360, 310 220 S 420 60, 460 180"
                stroke="#513DEF"
                strokeWidth="10"
                strokeLinecap="round"
                strokeLinejoin="round"
                fill="none"
                className="ink-stroke"
                style={{ ["--len" as string]: 1000, ["--delay" as string]: "0.2s" } as React.CSSProperties}
              />
              {/* Pressure dots */}
              <circle cx="460" cy="180" r="12" fill="#513DEF" opacity="0.35" />
              <circle cx="460" cy="180" r="6" fill="#513DEF" />
            </svg>
          {/* Dot paper hint at low opacity */}
          <div className="absolute inset-0 dot-grid opacity-30" />
        </div>
      </div>

      {/* Pressure badge */}
      <div className="absolute -top-3 right-6 glass rounded-full px-3 py-1.5 text-xs font-medium flex items-center gap-2">
        <span className="inline-block h-2 w-2 rounded-full bg-indigo animate-pulse" />
        <span className="text-ink-soft">pressure · 0.74</span>
      </div>

      {/* Little keycap hint */}
      <div className="absolute -bottom-4 left-6 flex items-center gap-2 text-xs text-mute">
        <Kbd>⌘</Kbd>
        <Kbd>D</Kbd>
        <span>toggles drawing mode</span>
      </div>
    </div>
  );
}

function Kbd({ children }: { children: React.ReactNode }) {
  return (
    <kbd className="inline-flex items-center justify-center min-w-6 h-6 px-1.5 rounded-md bg-white border border-black/10 shadow-[0_1px_0_rgba(0,0,0,0.06)] font-mono text-[11px]">
      {children}
    </kbd>
  );
}
