type Tool = "select" | "pen" | "highlighter" | "eraser" | "text" | "shape";

type Props = {
  active?: Tool;
  className?: string;
  compact?: boolean;
};

/**
 * Mini replica of the app's floating toolbar — glass material, rounded tiles,
 * the 7-color palette, and a width slider dot.
 */
export default function FloatingToolbar({
  active = "pen",
  className = "",
  compact = false,
}: Props) {
  return (
    <div
      className={`glass rounded-[18px] px-2.5 py-2 flex items-center gap-1.5 ${className}`}
    >
      <ToolBtn kind="select" active={active === "select"} />
      <ToolBtn kind="pen" active={active === "pen"} />
      <ToolBtn kind="highlighter" active={active === "highlighter"} />
      <ToolBtn kind="eraser" active={active === "eraser"} />
      <ToolBtn kind="text" active={active === "text"} />
      <ToolBtn kind="shape" active={active === "shape"} />
      {!compact && (
        <>
          <div className="w-px h-6 bg-black/10 mx-1" />
          <Palette />
          <div className="w-px h-6 bg-black/10 mx-1" />
          <WidthSlider />
        </>
      )}
    </div>
  );
}

function ToolBtn({ kind, active }: { kind: Tool; active: boolean }) {
  return (
    <button
      type="button"
      aria-label={kind}
      className={`h-9 w-9 rounded-[10px] grid place-items-center transition ${
        active
          ? "bg-indigo/[0.14] ring-[1.2px] ring-indigo/80 text-indigo"
          : "text-ink-soft hover:bg-black/[0.05]"
      }`}
    >
      <ToolIcon kind={kind} />
    </button>
  );
}

function ToolIcon({ kind }: { kind: Tool }) {
  const stroke = "currentColor";
  switch (kind) {
    case "select":
      return (
        <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
          <path
            d="M4 3 L15 10 L10 11 L8 16 Z"
            fill="currentColor"
          />
        </svg>
      );
    case "pen":
      return (
        <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
          <path
            d="M3 17 L5 12 L13 4 L16 7 L8 15 Z"
            stroke={stroke}
            strokeWidth="1.5"
            strokeLinejoin="round"
            strokeLinecap="round"
          />
          <path d="M3 17 L6 16" stroke={stroke} strokeWidth="1.5" strokeLinecap="round" />
        </svg>
      );
    case "highlighter":
      return (
        <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
          <path
            d="M5 16 L3 18 M5 16 L13 8 L16 11 L8 19 L5 16 Z"
            stroke={stroke}
            strokeWidth="1.5"
            strokeLinejoin="round"
            strokeLinecap="round"
          />
          <rect x="12" y="6" width="4" height="5" rx="0.8" transform="rotate(45 14 8.5)" fill={stroke} opacity="0.15" />
        </svg>
      );
    case "eraser":
      return (
        <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
          <path d="M6 16 L16 6 L18 8 L8 18 Z" stroke={stroke} strokeWidth="1.5" strokeLinejoin="round" />
          <path d="M6 16 L3 16 L3 13 L8 18" stroke={stroke} strokeWidth="1.5" strokeLinejoin="round" />
        </svg>
      );
    case "text":
      return (
        <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
          <path d="M5 5 H15 M10 5 V16" stroke={stroke} strokeWidth="1.6" strokeLinecap="round" />
        </svg>
      );
    case "shape":
      return (
        <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
          <rect x="3" y="6" width="9" height="9" rx="1" stroke={stroke} strokeWidth="1.5" />
          <circle cx="14" cy="7" r="3.5" stroke={stroke} strokeWidth="1.5" />
        </svg>
      );
  }
}

const palette = [
  { name: "black", hex: "#0E0E12" },
  { name: "indigo", hex: "#513DEF" },
  { name: "red", hex: "#E53A5B" },
  { name: "orange", hex: "#F7A333" },
  { name: "green", hex: "#38BC70" },
  { name: "blue", hex: "#2384F2" },
  { name: "purple", hex: "#9959F2" },
];

function Palette() {
  return (
    <div className="flex items-center gap-1">
      {palette.map((c, i) => (
        <button
          key={c.name}
          aria-label={c.name}
          className={`h-4 w-4 rounded-full shadow-[inset_0_0_0_0.5px_rgba(0,0,0,0.3)] ${
            i === 1 ? "ring-2 ring-offset-1 ring-indigo" : ""
          }`}
          style={{ background: c.hex }}
        />
      ))}
    </div>
  );
}

function WidthSlider() {
  return (
    <div className="flex items-center gap-1.5 px-1">
      <div className="w-1 h-1 rounded-full bg-ink-soft/70" />
      <div className="w-14 h-[3px] rounded-full bg-black/10 relative">
        <div className="absolute top-1/2 -translate-y-1/2 left-[55%] -translate-x-1/2 w-3 h-3 rounded-full bg-white shadow-[0_1px_2px_rgba(0,0,0,0.25),0_0_0_0.5px_rgba(0,0,0,0.15)]" />
      </div>
      <div className="w-2.5 h-2.5 rounded-full bg-ink-soft/70" />
    </div>
  );
}
