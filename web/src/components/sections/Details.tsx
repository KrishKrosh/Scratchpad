import { SectionEyebrow, SectionTitle } from "./Tools";

/**
 * A grid of smaller features — the things that don't headline but matter
 * once you're living in the app.
 */
const details = [
  {
    title: "Paper your way",
    body: "Dots, grid, lined, or blank. Infinite canvas or stacked pages.",
  },
  {
    title: "Autosave, actually",
    body: "Pauses you don't even notice. Your file is written before you look up.",
  },
  {
    title: "Undo that remembers",
    body: "Per-stroke undo wired through NSUndoManager. ⌘Z where it should be.",
  },
  {
    title: "Keyboard + trackpad",
    body: "Pan with scroll, ⌘-scroll to zoom, arrows with acceleration.",
  },
  {
    title: "Export anywhere",
    body: "PNG for the doc, PDF for the print, .scratchpad for the repo.",
  },
  {
    title: "Quiet by design",
    body: "No accounts. No cloud. No analytics. Just a window and a surface.",
  },
];

export default function Details() {
  return (
    <section className="py-24 md:py-32">
      <div className="mx-auto max-w-6xl px-6">
        <SectionEyebrow>The small print</SectionEyebrow>
        <SectionTitle>
          Things we&apos;d{" "}
          <span className="font-serif italic font-normal text-mute">
            rather not ship
          </span>{" "}
          without.
        </SectionTitle>

        <div className="mt-14 grid md:grid-cols-2 lg:grid-cols-3 gap-x-10 gap-y-10 max-w-4xl">
          {details.map((d) => (
            <div key={d.title}>
              <div className="flex items-center gap-2">
                <span className="h-1.5 w-1.5 rounded-full bg-indigo" />
                <h3 className="font-medium text-[17px]">{d.title}</h3>
              </div>
              <p className="mt-2 text-ink-soft/80 leading-relaxed">{d.body}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
