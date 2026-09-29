# Lucid Disk promo video

A 30-second, 1920×1080 motion design promo built with [Remotion](https://www.remotion.dev). Every scene is React code, so copy, timing and colors can be changed and re-rendered.

| Time | Scene | Message |
|---|---|---|
| 0–3 s | Intro | See your disk. Keep your judgment. |
| 3–8 s | Map | Sunburst, honest measurement |
| 8–13 s | Review | Review queue, re-checks, Trash only |
| 13–20 s | Lucid Insight | Apple on-device, Ollama, Claude — AI explains, you decide |
| 20–26.5 s | MCP | Five read-only tools for Claude Code, Claude Desktop, Codex |
| 26.5–30 s | Outro | Open source, GitHub link |

## Render

```bash
npm install
npm run render      # out/lucid-disk-promo.mp4
npm run studio      # live preview and timeline
```

Scene lengths live in `src/Promo.tsx`; colors and fonts (Geist, same as the website) in `src/theme.ts`. The video has no audio; add music or a voice-over in your editor. Numbers shown (54.2 GB, 1,284,311 files) are illustrative.
