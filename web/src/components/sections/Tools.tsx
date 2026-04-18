const tools = [
  {
    name: "Pen",
    hint: "Pressure-sensitive.",
    color: "#513DEF",
    body: (
      <svg viewBox="0 0 60 60" className="w-full h-full">
        <path
          d="M10 50 L18 30 L46 6 L54 14 L30 42 Z"
          fill="#513DEF"
          stroke="#0E0E12"
          strokeWidth="1.2"
          strokeLinejoin="round"
        />
        <path d="M10 50 L18 42" stroke="#0E0E12" strokeWidth="1.2" />
      </svg>
    ),
  },
  {
    name: "Highlighter",
    hint: "Warm, translucent.",
    color: "#F7A333",
    body: (
      <svg viewBox="0 0 60 60" className="w-full h-full">
        <rect x="34" y="4" width="16" height="30" rx="3" transform="rotate(35 42 19)" fill="#F7A333" stroke="#0E0E12" strokeWidth="1.2" />
        <path d="M12 48 L20 40 L28 48 L20 56 Z" fill="#F7A333" opacity="0.55" stroke="#0E0E12" strokeWidth="1.2" />
      </svg>
    ),
  },
  {
    name: "Eraser",
    hint: "Stroke-level, exact.",
    color: "#E53A5B",
    body: (
      <svg viewBox="0 0 60 60" className="w-full h-full">
        <rect x="6" y="28" width="40" height="18" rx="3" fill="#F7F5EF" stroke="#0E0E12" strokeWidth="1.2" />
        <rect x="6" y="28" width="14" height="18" rx="3" fill="#E53A5B" stroke="#0E0E12" strokeWidth="1.2" />
      </svg>
    ),
  },
  {
    name: "Select",
    hint: "Rect or lasso.",
    color: "#2384F2",
    body: (
      <svg viewBox="0 0 60 60" className="w-full h-full">
        <rect x="8" y="8" width="36" height="32" rx="2" stroke="#0E0E12" strokeWidth="1.4" strokeDasharray="4 4" fill="none" />
        <path d="M40 36 L52 46 L46 48 L44 54 Z" fill="#0E0E12" />
      </svg>
    ),
  },
  {
    name: "Text",
    hint: "Double-click, type.",
    color: "#0E0E12",
    body: (
      <svg viewBox="0 0 60 60" className="w-full h-full">
        <path d="M14 14 H46 M30 14 V50" stroke="#0E0E12" strokeWidth="3.6" strokeLinecap="round" />
      </svg>
    ),
  },
  {
    name: "Shapes",
    hint: "Rect, circle, line, arrow.",
    color: "#38BC70",
    body: (
      <svg viewBox="0 0 60 60" className="w-full h-full">
        <rect x="6" y="18" width="24" height="24" rx="2" stroke="#38BC70" strokeWidth="2.4" fill="none" />
        <circle cx="42" cy="18" r="10" stroke="#38BC70" strokeWidth="2.4" fill="none" />
        <path d="M30 46 L54 46 M50 42 L54 46 L50 50" stroke="#38BC70" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" fill="none" />
      </svg>
    ),
  },
];

export default function Tools() {
  return (
    <section id="tools" className="py-24 md:py-32">
      <div className="mx-auto max-w-6xl px-6">
        <SectionEyebrow>Toolbar</SectionEyebrow>
        <SectionTitle>
          Six tools.{" "}
          <span className="font-serif italic text-mute font-normal">
            no settings deep-dive.
          </span>
        </SectionTitle>
        <p className="mt-5 max-w-xl text-lg text-ink-soft/85">
          Everything on the surface, nothing hidden. The toolbar floats where
          you put it, snaps to edges, and gets out of the way when you draw.
        </p>

        <div className="mt-14 grid grid-cols-2 md:grid-cols-3 gap-5">
          {tools.map((t) => (
            <div
              key={t.name}
              data-ink={t.color}
              className="group relative rounded-2xl bg-white/60 border border-black/[0.06] p-6 flex flex-col gap-5 hover:bg-white transition"
            >
              <div className="h-16 w-16">{t.body}</div>
              <div>
                <div className="text-lg font-semibold">{t.name}</div>
                <div className="text-sm text-mute mt-0.5">{t.hint}</div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

export function SectionEyebrow({ children }: { children: React.ReactNode }) {
  return (
    <p className="text-[12px] uppercase tracking-[0.22em] text-indigo mb-4">
      {children}
    </p>
  );
}

export function SectionTitle({ children }: { children: React.ReactNode }) {
  return (
    <h2 className="font-sans text-3xl md:text-5xl leading-[1.05] tracking-[-0.02em] font-semibold max-w-3xl">
      {children}
    </h2>
  );
}
