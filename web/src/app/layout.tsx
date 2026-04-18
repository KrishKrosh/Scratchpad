import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono, Instrument_Serif } from "next/font/google";
import MarkerCursor from "@/components/MarkerCursor";
import "./globals.css";

const geist = Geist({
  variable: "--font-geist",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

const instrument = Instrument_Serif({
  variable: "--font-instrument",
  subsets: ["latin"],
  weight: "400",
  style: ["normal", "italic"],
});

export const metadata: Metadata = {
  metadataBase: new URL(
    process.env.NEXT_PUBLIC_SITE_URL ?? "https://scratchpad.app"
  ),
  title: "Scratchpad — think on your trackpad",
  description:
    "A macOS drawing scratchpad built for the trackpad surface. Freehand notes, handwritten math that converts to LaTeX, and a library that stays out of your way.",
  icons: {
    icon: "/icon.png",
    apple: "/icon-512.png",
  },
  openGraph: {
    title: "Scratchpad — think on your trackpad",
    description:
      "A macOS drawing scratchpad built for the trackpad surface. Freehand notes, handwritten math → LaTeX, a quiet library on your Mac.",
    images: ["/icon-1024.png"],
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Scratchpad",
    description:
      "Think on your trackpad. A macOS drawing scratchpad for quick ideas.",
    images: ["/icon-1024.png"],
  },
};

export const viewport: Viewport = {
  themeColor: "#f7f5ef",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html
      lang="en"
      className={`${geist.variable} ${geistMono.variable} ${instrument.variable}`}
    >
      <body className="font-sans min-h-dvh overflow-x-hidden">
        <MarkerCursor />
        {children}
      </body>
    </html>
  );
}
