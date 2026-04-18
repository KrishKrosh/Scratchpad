import { SectionEyebrow, SectionTitle } from "./Tools";

type Thumb = {
  title: string;
  when: string;
  paper: "dots" | "rule" | "blank";
  render: () => React.ReactNode;
};

const thumbs: Thumb[] = [
  {
    title: "Project Orion",
    when: "2 min ago",
    paper: "dots",
    render: () => (
      <svg viewBox="0 0 200 120" className="w-full h-full">
        <rect x="20" y="20" width="60" height="28" stroke="#0E0E12" strokeWidth="1.6" fill="none" />
        <path d="M82 34 L118 34 M114 30 L118 34 L114 38" stroke="#513DEF" strokeWidth="1.6" fill="none" strokeLinecap="round" strokeLinejoin="round" />
        <rect x="120" y="20" width="60" height="28" stroke="#0E0E12" strokeWidth="1.6" fill="none" />
        <path d="M40 80 c 10 -8, 30 8, 50 0 s 50 -10, 70 2" stroke="#E53A5B" strokeWidth="1.8" fill="none" strokeLinecap="round" />
      </svg>
    ),
  },
  {
    title: "standup-notes",
    when: "Yesterday",
    paper: "rule",
    render: () => (
      <svg viewBox="0 0 200 120" className="w-full h-full">
        <g stroke="#0E0E12" strokeWidth="1.4" fill="none" strokeLinecap="round">
          <path d="M20 30 l6 6 l12 -14" stroke="#38BC70" strokeWidth="2" />
          <path d="M40 36 h 100" />
          <path d="M20 60 l6 6 l12 -14" stroke="#38BC70" strokeWidth="2" />
          <path d="M40 66 h 120" />
          <path d="M22 90 h 18" />
          <path d="M40 96 h 90" />
        </g>
      </svg>
    ),
  },
  {
    title: "partial-derivatives",
    when: "3 days ago",
    paper: "dots",
    render: () => (
      <svg viewBox="0 0 200 120" className="w-full h-full">
        <g stroke="#513DEF" strokeWidth="2" fill="none" strokeLinecap="round">
          <path d="M22 74 c -8 0, -8 22, 6 22 s 16 -16, 12 -28 c -4 -10, -18 -4, -18 4" />
          <path d="M52 70 c 8 -6, 14 -2, 12 10 s -6 20, 2 20" />
          <path d="M72 60 h 8 M76 56 v 44" />
          <path d="M96 66 h 30 M96 82 h 30" />
          <path d="M140 66 c -12 0, -12 30, 6 30 s 16 -30, -6 -30" />
        </g>
      </svg>
    ),
  },
  {
    title: "landing-wireframe",
    when: "Last week",
    paper: "blank",
    render: () => (
      <svg viewBox="0 0 200 120" className="w-full h-full">
        <rect x="14" y="14" width="172" height="16" rx="3" stroke="#0E0E12" strokeWidth="1.4" fill="none" />
        <rect x="14" y="40" width="110" height="60" rx="3" stroke="#0E0E12" strokeWidth="1.4" fill="none" />
        <rect x="134" y="40" width="52" height="28" rx="3" stroke="#0E0E12" strokeWidth="1.4" fill="none" />
        <rect x="134" y="74" width="52" height="26" rx="3" stroke="#F7A333" strokeWidth="1.8" fill="none" />
      </svg>
    ),
  },
  {
    title: "flower",
    when: "2 weeks ago",
    paper: "dots",
    render: () => (
      <svg viewBox="0 0 200 120" className="w-full h-full">
        <g stroke="#9959F2" strokeWidth="1.8" fill="none" strokeLinecap="round">
          <circle cx="100" cy="60" r="10" />
          <path d="M100 30 c -18 8, -18 32, 0 20 M100 30 c 18 8, 18 32, 0 20" />
          <path d="M70 60 c 8 -18, 32 -18, 20 0 M70 60 c 8 18, 32 18, 20 0" />
          <path d="M130 60 c -8 -18, -32 -18, -20 0 M130 60 c -8 18, -32 18, -20 0" />
          <path d="M100 90 c -18 -8, -18 -32, 0 -20 M100 90 c 18 -8, 18 -32, 0 -20" />
        </g>
      </svg>
    ),
  },
  {
    title: "interview-loop",
    when: "Last month",
    paper: "rule",
    render: () => (
      <svg viewBox="0 0 200 120" className="w-full h-full">
        <g stroke="#2384F2" strokeWidth="1.6" fill="none" strokeLinecap="round">
          <circle cx="40" cy="60" r="16" />
          <path d="M56 60 h 30 M82 56 l 4 4 l -4 4" />
          <circle cx="100" cy="60" r="16" />
          <path d="M116 60 h 30 M142 56 l 4 4 l -4 4" />
          <rect x="158" y="44" width="30" height="30" rx="4" />
        </g>
      </svg>
    ),
  },
];

export default function Library() {
  return (
    <section id="library" className="py-24 md:py-32 bg-white/60 border-y border-black/[0.05]">
      <div className="mx-auto max-w-6xl px-6">
        <div className="grid md:grid-cols-[1fr_2fr] gap-14 md:gap-20 items-start">
          <div className="md:pt-4">
            <SectionEyebrow>Home</SectionEyebrow>
            <SectionTitle>
              A library,{" "}
              <span className="font-serif italic font-normal text-mute">
                not a folder.
              </span>
            </SectionTitle>
            <p className="mt-5 text-lg text-ink-soft/85 max-w-md">
              Every scratchpad autosaves the moment you stop drawing. Find
              them later in the Home window — by name, by date, by the
              shape of what you drew.
            </p>

            <div className="mt-6 text-sm text-mute space-y-1.5">
              <div>Stored as <code className="font-mono">.scratchpad</code> JSON.</div>
              <div>Export to PNG · PDF anytime.</div>
              <div>~/Documents/Scratchpad</div>
            </div>
          </div>

          <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
            {thumbs.map((t, i) => (
              <div
                key={t.title}
                className="group rounded-xl overflow-hidden bg-white border border-black/[0.06] hover:-translate-y-0.5 hover:shadow-[0_10px_30px_-12px_rgba(0,0,0,0.18)] transition"
                style={{ transform: `rotate(${(i % 3) - 1 ? ((i % 2 ? 0.6 : -0.5)) : 0}deg)` }}
              >
                <div
                  className={`h-[120px] ${
                    t.paper === "dots"
                      ? "bg-paper dot-grid"
                      : t.paper === "rule"
                      ? "bg-paper rule-paper"
                      : "bg-paper"
                  }`}
                >
                  {t.render()}
                </div>
                <div className="p-3">
                  <div className="text-sm font-medium truncate">{t.title}</div>
                  <div className="text-[11px] text-mute mt-0.5">{t.when}</div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
