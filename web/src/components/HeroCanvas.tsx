import AppWindow from "./AppWindow";
import FloatingToolbar from "./FloatingToolbar";

/**
 * The hero product shot: a macOS window, dot-paper canvas, a collection
 * of hand-drawn strokes animating in, and the floating toolbar resting
 * near the bottom.
 */
export default function HeroCanvas() {
  // Path length hints for the draw-in animation. Estimated once so the
  // dash offset and the pixel length match; a small over-estimate is fine.
  const strokes: Array<{
    d: string;
    color: string;
    w: number;
    len: number;
    delay: number;
    cap?: "round" | "square";
    dash?: string;
  }> = [
    // Big box
    {
      d: "M120 130 L360 130 L360 220 L120 220 Z",
      color: "#0E0E12",
      w: 2.4,
      len: 680,
      delay: 0.1,
    },
    // Box label
    {
      d: "M140 168 C 160 160, 180 176, 210 168 M220 168 C 240 172, 265 160, 300 170",
      color: "#0E0E12",
      w: 2,
      len: 260,
      delay: 0.6,
    },
    // Arrow out of box
    {
      d: "M360 175 C 420 175, 440 250, 500 265",
      color: "#513DEF",
      w: 2.6,
      len: 280,
      delay: 1.0,
    },
    // Arrow head
    {
      d: "M495 255 L506 266 L492 272",
      color: "#513DEF",
      w: 2.6,
      len: 60,
      delay: 1.55,
    },
    // Second box
    {
      d: "M510 260 L720 260 L720 345 L510 345 Z",
      color: "#0E0E12",
      w: 2.4,
      len: 590,
      delay: 1.65,
    },
    // Handwritten label inside second box — fake cursive
    {
      d: "M528 305 c 10 -20, 20 10, 35 0 s 30 -20, 45 0 s 35 12, 55 -6 s 40 10, 60 -4",
      color: "#513DEF",
      w: 2.2,
      len: 320,
      delay: 2.1,
    },
    // Big circled word "focus!"
    {
      d: "M170 330 c -25 -6 -32 35, 0 40 s 70 -2, 68 -22 s -40 -24, -68 -18",
      color: "#E53A5B",
      w: 2.6,
      len: 240,
      delay: 2.7,
    },
    // Focus squiggle inside
    {
      d: "M175 345 c 8 -6, 14 6, 22 0 s 14 -6, 22 2",
      color: "#E53A5B",
      w: 2.2,
      len: 70,
      delay: 3.1,
    },
    // A star
    {
      d: "M640 130 l 10 22 l 24 3 l -18 16 l 5 23 l -21 -12 l -21 12 l 5 -23 l -18 -16 l 24 -3 Z",
      color: "#F7A333",
      w: 2.2,
      len: 170,
      delay: 3.3,
    },
    // Small TODO check
    {
      d: "M320 400 l 8 8 l 18 -22",
      color: "#38BC70",
      w: 3,
      len: 50,
      delay: 3.7,
    },
  ];

  return (
    <div className="relative">
      <AppWindow
        title="Project Orion"
        tab="autosaved · just now"
        className="floaty"
      >
        <div className="relative h-[460px] bg-paper-warm dot-grid dot-grid-fade">
          <svg
            viewBox="0 0 840 460"
            className="absolute inset-0 w-full h-full"
            preserveAspectRatio="xMidYMid meet"
          >
            {strokes.map((s, i) => (
              <path
                key={i}
                d={s.d}
                fill="none"
                stroke={s.color}
                strokeWidth={s.w}
                strokeLinecap={s.cap ?? "round"}
                strokeLinejoin="round"
                className="ink-stroke"
                style={
                  {
                    ["--len" as string]: s.len,
                    ["--delay" as string]: `${s.delay}s`,
                  } as React.CSSProperties
                }
              />
            ))}

            {/* Static text labels — rendered as proper text, not strokes */}
            <text
              x="240"
              y="195"
              className="fill-ink"
              fontFamily="var(--font-instrument), serif"
              fontStyle="italic"
              fontSize="22"
              textAnchor="middle"
            >
              idea
            </text>
            <text
              x="615"
              y="320"
              className="fill-indigo"
              fontFamily="var(--font-instrument), serif"
              fontStyle="italic"
              fontSize="22"
              textAnchor="middle"
            >
              ship it
            </text>
          </svg>
        </div>
      </AppWindow>

      {/* Floating toolbar overlapping the bottom of the window */}
      <div className="absolute left-1/2 -translate-x-1/2 -bottom-6 z-10">
        <FloatingToolbar active="pen" />
      </div>
    </div>
  );
}
