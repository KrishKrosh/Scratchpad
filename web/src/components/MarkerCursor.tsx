"use client";

import { useEffect, useRef } from "react";

/**
 * MarkerCursor — replaces the native cursor with a marker nib that leaves
 * an ink trail. Strokes fade after ~900ms. Color cycles with the `data-ink`
 * attribute on any ancestor under the pointer (so feature sections can
 * "dip" the cursor in a different color).
 *
 * Disabled on coarse pointers (touch) — the native cursor is restored and
 * no listeners are attached.
 */
export default function MarkerCursor() {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const nibRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const isCoarse = window.matchMedia("(pointer: coarse)").matches;
    if (isCoarse) {
      // Touch devices: give back the native cursor and skip the whole rig.
      document.documentElement.style.cursor = "auto";
      document.body.style.cursor = "auto";
      return;
    }
    const canvas = canvasRef.current!;
    const nib = nibRef.current!;
    const ctx = canvas.getContext("2d")!;
    let dpr = Math.min(window.devicePixelRatio || 1, 2);

    const resize = () => {
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = window.innerWidth * dpr;
      canvas.height = window.innerHeight * dpr;
      canvas.style.width = window.innerWidth + "px";
      canvas.style.height = window.innerHeight + "px";
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    resize();
    window.addEventListener("resize", resize);

    type Pt = { x: number; y: number; t: number; color: string; w: number };
    const points: Pt[] = [];
    const FADE_MS = 900;
    const MAX_POINTS = 240;

    let cx = window.innerWidth / 2;
    let cy = window.innerHeight / 2;
    let tx = cx;
    let ty = cy;
    let lastMove = performance.now();
    let down = false;
    let currentColor = "#513DEF";
    let targetHover: "text" | "button" | null = null;

    const readHover = (el: Element | null) => {
      const inkEl = el?.closest?.("[data-ink]") as HTMLElement | null;
      currentColor = inkEl?.dataset.ink || "#513DEF";
      const hoverEl = el?.closest?.("a,button,[role=button]") as HTMLElement | null;
      const textEl = el?.closest?.("input,textarea,[contenteditable=true]") as HTMLElement | null;
      targetHover = textEl ? "text" : hoverEl ? "button" : null;
    };

    const onMove = (e: PointerEvent) => {
      tx = e.clientX;
      ty = e.clientY;
      readHover(document.elementFromPoint(tx, ty));
      lastMove = performance.now();
    };
    const onDown = () => {
      down = true;
    };
    const onUp = () => {
      down = false;
    };
    const onLeave = () => {
      nib.style.opacity = "0";
    };
    const onEnter = () => {
      nib.style.opacity = "1";
    };

    window.addEventListener("pointermove", onMove, { passive: true });
    window.addEventListener("pointerdown", onDown);
    window.addEventListener("pointerup", onUp);
    document.addEventListener("mouseleave", onLeave);
    document.addEventListener("mouseenter", onEnter);

    let raf = 0;
    const tick = () => {
      const now = performance.now();
      // Smooth interpolation toward pointer (felt-tip weight)
      const ease = 0.28;
      const px = cx;
      const py = cy;
      cx += (tx - cx) * ease;
      cy += (ty - cy) * ease;

      const dist = Math.hypot(cx - px, cy - py);
      // Only record an ink point if we actually moved (avoids ink puddling)
      if (dist > 0.6 && now - lastMove < 1500) {
        const baseWeight = targetHover === "button" ? 5.5 : 3.4;
        const speedGain = Math.min(dist * 0.45, 4);
        points.push({
          x: cx,
          y: cy,
          t: now,
          color: currentColor,
          w: baseWeight + speedGain,
        });
        if (points.length > MAX_POINTS) points.shift();
      }

      // Clear and redraw trail with time-based alpha decay
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.lineCap = "round";
      ctx.lineJoin = "round";

      for (let i = 1; i < points.length; i++) {
        const a = points[i - 1];
        const b = points[i];
        const age = now - b.t;
        if (age > FADE_MS) continue;
        const alpha = 1 - age / FADE_MS;
        ctx.strokeStyle = hexWithAlpha(b.color, alpha * 0.9);
        ctx.lineWidth = b.w * alpha;
        ctx.beginPath();
        ctx.moveTo(a.x, a.y);
        // Quadratic smoothing to previous midpoint for a nicer line
        const mx = (a.x + b.x) / 2;
        const my = (a.y + b.y) / 2;
        ctx.quadraticCurveTo(a.x, a.y, mx, my);
        ctx.stroke();
      }

      // Drop stale points
      while (points.length && now - points[0].t > FADE_MS) points.shift();

      // Nib — a small circular dot that rides the pointer
      const scale = down ? 0.82 : targetHover === "button" ? 1.35 : 1;
      const hide = targetHover === "text";
      nib.style.transform = `translate3d(${cx}px, ${cy}px, 0) scale(${scale})`;
      nib.style.setProperty("--nib-color", currentColor);
      nib.style.opacity = hide ? "0" : "1";

      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("resize", resize);
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerdown", onDown);
      window.removeEventListener("pointerup", onUp);
      document.removeEventListener("mouseleave", onLeave);
      document.removeEventListener("mouseenter", onEnter);
    };
  }, []);

  return (
    <>
      <canvas
        ref={canvasRef}
        aria-hidden
        className="pointer-events-none fixed inset-0 z-[9998]"
      />
      <div
        ref={nibRef}
        aria-hidden
        className="pointer-events-none fixed left-0 top-0 z-[9999] origin-center transition-opacity duration-150"
        style={{ willChange: "transform" }}
      >
        <Nib />
      </div>
    </>
  );
}

function Nib() {
  // A small inked dot that sits exactly under the pointer.
  // Outer ring gives it presence; inner fill picks up the contextual ink color.
  const size = 14;
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 14 14"
      fill="none"
      style={{ transform: `translate(-${size / 2}px, -${size / 2}px)` }}
    >
      <circle
        cx="7"
        cy="7"
        r="5.5"
        fill="var(--nib-color, #513DEF)"
        opacity="0.95"
      />
      <circle
        cx="7"
        cy="7"
        r="5.5"
        fill="none"
        stroke="rgba(255,255,255,0.65)"
        strokeWidth="1"
      />
    </svg>
  );
}

function hexWithAlpha(hex: string, alpha: number) {
  // Supports #RGB, #RRGGBB
  let h = hex.replace("#", "");
  if (h.length === 3) h = h.split("").map((c) => c + c).join("");
  const r = parseInt(h.slice(0, 2), 16);
  const g = parseInt(h.slice(2, 4), 16);
  const b = parseInt(h.slice(4, 6), 16);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}
