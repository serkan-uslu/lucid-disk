import { loadFont } from "@remotion/google-fonts/Geist";
import { loadFont as loadMono } from "@remotion/google-fonts/GeistMono";

// Same typeface and palette as the website and the app's accent.
export const { fontFamily } = loadFont("normal", {
  weights: ["400", "500", "600", "700"],
  subsets: ["latin"],
});
export const { fontFamily: monoFamily } = loadMono("normal", {
  weights: ["400", "600"],
  subsets: ["latin"],
});

export const color = {
  ink: "#061116",
  panel: "#0b1920",
  panelSoft: "#0f222b",
  line: "rgba(255,255,255,0.09)",
  text: "#eef9fa",
  muted: "#8fa8b1",
  cyan: "#4dd3e3",
  green: "#42d6aa",
  amber: "#f0a63c",
  red: "#ff6b6b",
  purple: "#8b7cf6",
  pink: "#e77ad8",
  blue: "#5b8def",
};

/** Chart palette in the same contrasting order as the app. */
export const chart = ["#4ed4e5", "#8b7cf6", "#e7a85d", "#6fd08c", "#5b8def", "#e77ad8"];
