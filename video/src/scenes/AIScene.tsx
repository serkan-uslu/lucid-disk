import { interpolate, useCurrentFrame } from "remotion";
import { Card, Headline, Pill, typed, useEnter } from "../components";
import { color } from "../theme";

const providers = [
  { name: "Apple on-device", badge: "On this Mac", tint: color.green },
  { name: "Ollama", badge: "Local model", tint: color.green },
  { name: "Claude API", badge: "Your key · opt-in", tint: color.amber },
];

const answer = "Xcode’s build and index cache. Xcode recreates it on the next build.";

export const AIScene = () => {
  const frame = useCurrentFrame();
  const enter = useEnter(0, 16);
  // The highlight walks across providers, then settles on Ollama.
  const active = frame < 40 ? 0 : frame < 62 ? 1 : frame < 84 ? 2 : 1;
  const press = interpolate(frame, [96, 102, 108], [1, 0.9, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const insight = useEnter(104, 18);
  const text = typed(answer, frame, 112, 52);
  const rule = useEnter(170);
  return (
    <>
      <Headline
        label="LUCID INSIGHT"
        title={
          <>
            AI explains.
            <br />
            <span style={{ color: color.cyan }}>You decide.</span>
          </>
        }
        sub="Ask what an unfamiliar folder is — with the model you choose. File contents are never read."
      />
      <div style={{ position: "absolute", right: 140, top: 140, width: 780, opacity: enter, transform: `translateY(${(1 - enter) * 40}px)` }}>
        <div style={{ display: "grid", gap: 14 }}>
          {providers.map((p, i) => {
            const on = i === active;
            return (
              <div
                key={p.name}
                style={{
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "space-between",
                  padding: "22px 28px",
                  borderRadius: 20,
                  border: `2px solid ${on ? color.cyan : color.line}`,
                  background: on ? "rgba(77,211,227,0.10)" : "rgba(255,255,255,0.04)",
                  fontSize: 32,
                  fontWeight: 600,
                }}
              >
                <span>
                  <span style={{ color: on ? color.cyan : color.muted, marginRight: 16 }}>{on ? "●" : "○"}</span>
                  {p.name}
                </span>
                <Pill text={p.badge} tint={p.tint} style={{ fontSize: 20 }} />
              </div>
            );
          })}
        </div>
        <Card style={{ marginTop: 26, padding: 34, minHeight: 300 }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <span style={{ color: color.cyan, fontSize: 26, fontWeight: 700 }}>✦ Lucid Insight</span>
            <span
              style={{
                padding: "12px 26px",
                borderRadius: 12,
                background: color.cyan,
                color: color.ink,
                fontSize: 24,
                fontWeight: 700,
                transform: `scale(${press})`,
              }}
            >
              Ask AI
            </span>
          </div>
          <div style={{ marginTop: 26, fontSize: 32, lineHeight: 1.45, minHeight: 96, opacity: insight }}>
            {text}
            {text.length < answer.length && frame >= 112 ? <span style={{ color: color.cyan }}>▍</span> : null}
          </div>
          <div style={{ marginTop: 18, display: "flex", gap: 12, opacity: rule }}>
            <Pill text="Ollama · local" tint={color.cyan} style={{ fontSize: 19 }} />
            <Pill text="Risk stays deterministic" tint={color.green} style={{ fontSize: 19 }} />
          </div>
        </Card>
      </div>
    </>
  );
};
