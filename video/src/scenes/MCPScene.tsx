import { interpolate, useCurrentFrame } from "remotion";
import { Card, Headline, Pill, typed, useEnter } from "../components";
import { color, monoFamily } from "../theme";

const command = "claude mcp add luciddisk -- uv run --project ./mcp luciddisk-mcp";
const tools = [
  "summarize_known_locations",
  "inventory_directory",
  "find_large_files",
  "assess_paths",
  "create_cleanup_plan",
];

const bubble = (v: number, align: "flex-start" | "flex-end") => ({
  alignSelf: align,
  opacity: v,
  transform: `translateY(${(1 - v) * 20}px)`,
});

export const MCPScene = () => {
  const frame = useCurrentFrame();
  const enter = useEnter(0, 16);
  const cmd = typed(command, frame, 8, 70);
  const user = useEnter(46);
  const tool = useEnter(62);
  const reply = useEnter(78);
  return (
    <>
      <Headline
        label="MCP SERVER"
        title={
          <>
            Eyes for your
            <br />
            assistant.
            <br />
            <span style={{ color: color.cyan }}>No hands.</span>
          </>
        }
        sub="Five read-only tools for Claude Code, Claude Desktop and Codex. Nothing can be deleted."
      />
      <Card
        style={{
          position: "absolute",
          right: 140,
          top: 130,
          width: 800,
          overflow: "hidden",
          opacity: enter,
          transform: `translateY(${(1 - enter) * 40}px)`,
        }}
      >
        <div style={{ display: "flex", gap: 10, padding: "20px 26px", borderBottom: `1px solid ${color.line}` }}>
          {["#ff6b6b", "#f0c14b", "#42d6aa"].map((c) => (
            <span key={c} style={{ width: 14, height: 14, borderRadius: 7, background: c, opacity: 0.8 }} />
          ))}
        </div>
        <div style={{ padding: "24px 30px", fontFamily: monoFamily, fontSize: 23, lineHeight: 1.6, minHeight: 110, borderBottom: `1px solid ${color.line}` }}>
          <span style={{ color: color.green }}>$ </span>
          {cmd}
          {cmd.length < command.length ? <span style={{ color: color.cyan }}>▍</span> : null}
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 16, padding: 30 }}>
          <div style={{ ...bubble(user, "flex-end"), padding: "16px 22px", borderRadius: 18, background: color.cyan, color: color.ink, fontSize: 26, fontWeight: 600 }}>
            What’s eating my disk?
          </div>
          <div style={{ ...bubble(tool, "flex-start"), padding: "10px 18px", borderRadius: 12, background: "rgba(255,255,255,0.06)", color: color.muted, fontFamily: monoFamily, fontSize: 20 }}>
            ⌘ summarize_known_locations
          </div>
          <div style={{ ...bubble(reply, "flex-start"), maxWidth: 620, padding: "16px 22px", borderRadius: 18, background: "rgba(255,255,255,0.08)", fontSize: 26, lineHeight: 1.45 }}>
            DerivedData uses <b style={{ color: color.cyan }}>54.2 GB</b> and is rebuildable. Downloads has{" "}
            <b style={{ color: color.cyan }}>18.7 GB</b> to review first.
          </div>
        </div>
      </Card>
      <div style={{ position: "absolute", right: 140, top: 690, width: 800, display: "flex", flexWrap: "wrap", gap: 12 }}>
        {tools.map((name, i) => {
          const v = interpolate(frame, [96 + i * 8, 108 + i * 8], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
          return (
            <span
              key={name}
              style={{
                padding: "10px 16px",
                borderRadius: 12,
                border: "1px solid rgba(77,211,227,0.3)",
                color: "#7fe3ef",
                fontFamily: monoFamily,
                fontSize: 20,
                opacity: v,
                transform: `translateY(${(1 - v) * 16}px)`,
              }}
            >
              {name}
            </span>
          );
        })}
        <Pill
          text="readOnlyHint: true"
          tint={color.green}
          style={{ fontSize: 20, opacity: interpolate(frame, [140, 152], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }) }}
        />
      </div>
    </>
  );
};
