import { AbsoluteFill, Img, staticFile } from "remotion";
import { color, fontFamily } from "./theme";

export type GalleryProps = {
  eyebrow: string;
  title: string;
  subtitle: string;
  shot: string;
  /** Tall settings-style shots are shown narrower. */
  tall?: boolean;
};

/** A 1270×760 store image: headline on the left, a real app screenshot on the right. */
export const Gallery = ({ eyebrow, title, subtitle, shot, tall }: GalleryProps) => (
  <AbsoluteFill
    style={{
      fontFamily,
      color: color.text,
      background:
        "radial-gradient(circle at 78% 40%, rgba(59,130,246,0.28), transparent 45%), radial-gradient(circle at 20% 90%, rgba(77,216,232,0.12), transparent 40%), #05090f",
    }}
  >
    <div style={{ position: "absolute", left: 64, top: 0, bottom: 0, width: 400, display: "flex", flexDirection: "column", justifyContent: "center" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
        <Img src={staticFile("app-icon.png")} style={{ width: 44, height: 44 }} />
        <span style={{ fontSize: 22, fontWeight: 600 }}>Lucid Disk</span>
      </div>
      <div style={{ marginTop: 40, color: color.cyan, fontSize: 17, fontWeight: 700, letterSpacing: "0.14em", textTransform: "uppercase" }}>
        {eyebrow}
      </div>
      <div style={{ marginTop: 14, fontSize: 52, fontWeight: 600, letterSpacing: "-0.045em", lineHeight: 1.02 }}>{title}</div>
      <div style={{ marginTop: 20, color: color.muted, fontSize: 21, lineHeight: 1.45 }}>{subtitle}</div>
    </div>
    <Img
      src={staticFile(`gallery/${shot}.webp`)}
      style={{
        position: "absolute",
        right: tall ? 70 : -60,
        top: "50%",
        transform: "translateY(-50%)",
        width: tall ? 520 : 820,
        filter: "drop-shadow(0 30px 60px rgba(0,0,0,0.6))",
      }}
    />
  </AbsoluteFill>
);

export const galleryItems: (GalleryProps & { id: string })[] = [
  { id: "ph-1-map", eyebrow: "Free · open source", title: "See where your space went.", subtitle: "A live sunburst of your folders. Click in, zoom out, search everything.", shot: "overview" },
  { id: "ph-2-system-data", eyebrow: "Space breakdown", title: "Finally: what is System Data?", subtitle: "macOS volumes, snapshots and hidden system files — explained, and adding up exactly.", shot: "space", tall: true },
  { id: "ph-3-review", eyebrow: "Review", title: "You decide what goes.", subtitle: "Select several, queue, confirm once. Trash only — every item re-checked.", shot: "batch" },
  { id: "ph-4-ai", eyebrow: "Ask AI", title: "AI explains. You decide.", subtitle: "Apple on-device, Ollama or Claude. Metadata only, never file contents.", shot: "ai", tall: true },
  { id: "ph-5-mcp", eyebrow: "MCP server", title: "Eyes for your assistant. No hands.", subtitle: "Five read-only tools for Claude Code, Claude Desktop and Codex.", shot: "mcp", tall: true },
];
