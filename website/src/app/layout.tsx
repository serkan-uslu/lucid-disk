import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "https://lucid-disk.vercel.app";
const description =
  "A free, open-source disk space analyzer for macOS. See where your space went, find out what System Data really is, ask AI what unfamiliar files are, and clean up only what you approve.";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: "Lucid Disk — See your disk. Keep your judgment.",
  description,
  applicationName: "Lucid Disk",
  keywords: [
    "macOS disk space analyzer",
    "disk usage visualizer",
    "System Data macOS",
    "open source Mac cleaner",
    "free disk analyzer",
    "on-device AI",
    "Ollama",
    "MCP server",
  ],
  openGraph: {
    type: "website",
    url: siteUrl,
    siteName: "Lucid Disk",
    title: "Lucid Disk — See your disk. Keep your judgment.",
    description,
  },
  twitter: {
    card: "summary_large_image",
    title: "Lucid Disk — See your disk. Keep your judgment.",
    description,
  },
};

export const viewport: Viewport = {
  themeColor: "#05090f",
  colorScheme: "dark",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable}`}
      data-scroll-behavior="smooth"
    >
      <body>{children}</body>
    </html>
  );
}
