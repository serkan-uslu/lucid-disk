import { interpolate, useCurrentFrame } from "remotion";
import { Card, Headline, Pill, useEnter } from "../components";
import { color } from "../theme";

const checks = ["Path and identity re-checked", "Protected paths stay blocked", "Moved to Trash — restore anytime"];

export const ReviewScene = () => {
  const frame = useCurrentFrame();
  const card = useEnter(0, 16);
  const press = interpolate(frame, [34, 40, 46], [1, 0.94, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const queued = frame >= 42;
  const slide = useEnter(44, 16);
  return (
    <>
      <Headline
        label="REVIEW"
        title={
          <>
            You decide
            <br />
            what goes.
          </>
        }
        sub="Nothing is removed automatically. Every item is checked again before it moves to Trash."
      />
      <div style={{ position: "absolute", right: 140, top: 180, width: 780, opacity: card, transform: `translateY(${(1 - card) * 40}px)` }}>
        <Card style={{ padding: 40 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 24 }}>
            <div
              style={{
                width: 72,
                height: 60,
                borderRadius: "10px 10px 14px 14px",
                background: "linear-gradient(180deg,#7fd8f0,#3aa9d6)",
                boxShadow: "inset 0 10px rgba(255,255,255,0.25)",
              }}
            />
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 38, fontWeight: 600 }}>DerivedData</div>
              <div style={{ fontSize: 22, color: color.muted }}>~/Library/Developer/Xcode</div>
            </div>
            <div style={{ fontSize: 40, fontWeight: 600 }}>54.2 GB</div>
          </div>
          <div style={{ marginTop: 26 }}>
            <Pill text="↻  Rebuildable" tint={color.green} />
          </div>
          <div
            style={{
              marginTop: 30,
              padding: "22px 26px",
              borderRadius: 16,
              fontSize: 28,
              fontWeight: 600,
              transform: `scale(${press})`,
              color: queued ? color.ink : color.text,
              background: queued ? color.cyan : "rgba(255,255,255,0.07)",
            }}
          >
            {queued ? "✓  In Review Queue" : "+  Add to Review Queue"}
          </div>
        </Card>
        <div style={{ marginTop: 26, display: "grid", gap: 16 }}>
          {checks.map((text, i) => {
            const v = interpolate(slide, [0, 1], [0, 1]) * interpolate(frame, [58 + i * 14, 70 + i * 14], [0, 1], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
            });
            return (
              <div
                key={text}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 18,
                  padding: "18px 26px",
                  borderRadius: 16,
                  border: `1px solid ${color.line}`,
                  background: "rgba(255,255,255,0.04)",
                  fontSize: 27,
                  opacity: v,
                  transform: `translateX(${(1 - v) * 40}px)`,
                }}
              >
                <span style={{ color: color.green, fontWeight: 700 }}>✓</span>
                {text}
              </div>
            );
          })}
        </div>
      </div>
    </>
  );
};
