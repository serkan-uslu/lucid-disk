import type React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { Card, Headline, Pill, useEnter } from "../components";
import { chart, color, monoFamily } from "../theme";

type Slice = { share: number; children?: number[] };

// Shares of the parent, largest first, as the app draws them.
const slices: Slice[] = [
  { share: 0.3, children: [0.45, 0.3, 0.15, 0.1] },
  { share: 0.22, children: [0.5, 0.3, 0.2] },
  { share: 0.17, children: [0.6, 0.4] },
  { share: 0.13, children: [0.35, 0.35, 0.3] },
  { share: 0.1, children: [0.7, 0.3] },
  { share: 0.08, children: [0.5, 0.5] },
];

const polar = (cx: number, cy: number, r: number, deg: number) => {
  const rad = ((deg - 90) * Math.PI) / 180;
  return [cx + r * Math.cos(rad), cy + r * Math.sin(rad)];
};

const arc = (cx: number, cy: number, r0: number, r1: number, a0: number, a1: number) => {
  const sweep = Math.max(0.01, a1 - a0);
  const large = sweep > 180 ? 1 : 0;
  const [x0, y0] = polar(cx, cy, r1, a0);
  const [x1, y1] = polar(cx, cy, r1, a0 + sweep);
  const [x2, y2] = polar(cx, cy, r0, a0 + sweep);
  const [x3, y3] = polar(cx, cy, r0, a0);
  return `M${x0},${y0} A${r1},${r1} 0 ${large} 1 ${x1},${y1} L${x2},${y2} A${r0},${r0} 0 ${large} 0 ${x3},${y3} Z`;
};

export const MapScene = () => {
  const frame = useCurrentFrame();
  const inner = useEnter(6, 20);
  const outer = useEnter(22, 20);
  const card = useEnter(0, 16);
  const cx = 360;
  const cy = 360;
  const bytes = interpolate(frame, [6, 110], [0, 482.6], { extrapolateRight: "clamp" });
  const files = Math.round(interpolate(frame, [6, 110], [0, 1284311], { extrapolateRight: "clamp" }));
  const chipA = useEnter(70);
  const chipB = useEnter(82);

  let start = 0;
  const wedges: React.ReactNode[] = [];
  slices.forEach((slice, i) => {
    const span = slice.share * 360;
    wedges.push(
      <path
        key={`in-${i}`}
        d={arc(cx, cy, 128, 222, start * inner, (start + span) * inner)}
        fill={chart[i]}
        stroke={color.panel}
        strokeWidth={3}
      />,
    );
    let childStart = start;
    slice.children?.forEach((share, j) => {
      const childSpan = span * share;
      wedges.push(
        <path
          key={`out-${i}-${j}`}
          d={arc(cx, cy, 228, 318, childStart * outer, (childStart + childSpan) * outer)}
          fill={chart[i]}
          opacity={0.72 - j * 0.1}
          stroke={color.panel}
          strokeWidth={3}
        />,
      );
      childStart += childSpan;
    });
    start += span;
  });

  return (
    <>
      <Headline
        label="MAP"
        title={
          <>
            Every byte,
            <br />
            at a glance.
          </>
        }
        sub="A live sunburst of your folders. Click in, zoom out, search everything."
      />
      <Card
        style={{
          position: "absolute",
          right: 140,
          top: 150,
          width: 780,
          height: 780,
          opacity: card,
          transform: `translateY(${(1 - card) * 40}px)`,
        }}
      >
        <svg width={720} height={720} viewBox="0 0 720 720" style={{ margin: 30 }}>
          {wedges}
          <circle cx={cx} cy={cy} r={120} fill={color.panelSoft} stroke="rgba(77,211,227,0.35)" strokeWidth={2} />
          <text x={cx} y={cy - 4} textAnchor="middle" fill={color.text} fontSize={46} fontWeight={600}>
            {bytes.toFixed(1)} GB
          </text>
          <text x={cx} y={cy + 44} textAnchor="middle" fill={color.muted} fontSize={20} fontFamily={monoFamily}>
            {files.toLocaleString("en-US")} files
          </text>
        </svg>
      </Card>
      <div style={{ position: "absolute", left: 140, top: 760, display: "flex", gap: 14 }}>
        <Pill text="Hard links counted once" tint={color.cyan} style={{ opacity: chipA }} />
        <Pill text="Partial scans labeled" tint={color.cyan} style={{ opacity: chipB }} />
      </div>
    </>
  );
};
