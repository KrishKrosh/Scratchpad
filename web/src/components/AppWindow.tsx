import { ReactNode } from "react";

type Props = {
  title?: string;
  children: ReactNode;
  className?: string;
  tab?: string;
};

/**
 * Faithful macOS window chrome — title bar, traffic lights, document tab.
 * The children render inside the canvas area (which defaults to the
 * paper color). Composable with DotPaper or RulePaper backgrounds.
 */
export default function AppWindow({ title = "Untitled", children, className = "", tab }: Props) {
  return (
    <div
      className={`relative rounded-[14px] bg-white window-shadow overflow-hidden ${className}`}
    >
      {/* Title bar */}
      <div className="relative flex items-center h-10 px-3.5 border-b border-black/[0.06] bg-[linear-gradient(to_bottom,#fbfaf7,#f2f0ea)]">
        <div className="flex gap-1.5">
          <span className="h-3 w-3 rounded-full bg-[#ff5f57] shadow-[inset_0_0_0_0.5px_rgba(0,0,0,0.18)]" />
          <span className="h-3 w-3 rounded-full bg-[#febc2e] shadow-[inset_0_0_0_0.5px_rgba(0,0,0,0.18)]" />
          <span className="h-3 w-3 rounded-full bg-[#28c840] shadow-[inset_0_0_0_0.5px_rgba(0,0,0,0.18)]" />
        </div>
        <div className="absolute inset-x-0 mx-auto flex justify-center pointer-events-none">
          <span className="text-[12px] font-medium text-ink-soft/80 tabular-nums">
            {title}
          </span>
        </div>
        {tab && (
          <div className="ml-auto text-[11px] font-medium text-mute">{tab}</div>
        )}
      </div>
      {/* Canvas area */}
      <div className="relative">{children}</div>
    </div>
  );
}
