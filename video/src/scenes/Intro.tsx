import { Img, interpolate, staticFile, useCurrentFrame } from "remotion";
import { useEnter } from "../components";
import { color } from "../theme";

export const Intro = () => {
  const frame = useCurrentFrame();
  const icon = useEnter(0, 14);
  const line1 = useEnter(14);
  const line2 = useEnter(24);
  const glow = interpolate(frame, [0, 60], [0.2, 0.7], { extrapolateRight: "clamp" });
  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <Img
        src={staticFile("app-icon.png")}
        style={{
          width: 190,
          height: 190,
          transform: `scale(${0.6 + icon * 0.4}) rotate(${(1 - icon) * -30}deg)`,
          opacity: icon,
          filter: `drop-shadow(0 0 ${50 * glow}px rgba(77,211,227,${glow}))`,
        }}
      />
      <div
        style={{
          marginTop: 56,
          fontSize: 118,
          fontWeight: 600,
          letterSpacing: "-0.06em",
          lineHeight: 1,
          opacity: line1,
          transform: `translateY(${(1 - line1) * 30}px)`,
        }}
      >
        See your disk.
      </div>
      <div
        style={{
          marginTop: 10,
          fontSize: 118,
          fontWeight: 600,
          letterSpacing: "-0.06em",
          lineHeight: 1,
          color: color.cyan,
          opacity: line2,
          transform: `translateY(${(1 - line2) * 30}px)`,
        }}
      >
        Keep your judgment.
      </div>
    </div>
  );
};
