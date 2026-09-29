import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "https://lucid-disk.vercel.app";
const description =
  "Find what's taking up space on your Mac, understand unfamiliar files and System Data, and move only what you review and confirm to the Trash.";
const title = "Lucid Disk — Understand What’s Taking Up Space on Your Mac";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title,
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
    title,
    description,
  },
  twitter: {
    card: "summary_large_image",
    title,
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
