import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { color, fontFamily } from "./theme";

/** Smooth 0→1 entrance that starts `delay` frames into the scene. */
export const useEnter = (delay = 0, damping = 18) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: frame - delay, fps, config: { damping, mass: 0.8 } });
};

export const Background: React.FC = () => {
  const frame = useCurrentFrame();
  const drift = interpolate(frame, [0, 900], [0, -64]);
  return (
    <AbsoluteFill style={{ backgroundColor: color.ink }}>
      <AbsoluteFill
        style={{
          backgroundImage:
            "linear-gradient(rgba(255,255,255,0.03) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.03) 1px, transparent 1px)",
          backgroundSize: "64px 64px",
          backgroundPosition: `${drift}px ${drift}px`,
          maskImage: "radial-gradient(ellipse at 30% 40%, black, transparent 75%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          right: -300,
          top: -120,
          width: 1300,
          height: 1100,
          borderRadius: "50%",
          background:
            "radial-gradient(circle, rgba(53,203,221,0.18), rgba(72,95,237,0.08) 40%, transparent 70%)",
          filter: "blur(30px)",
        }}
      />
    </AbsoluteFill>
  );
};

/** Fades a scene in and out so hard cuts never flash. */
export const SceneFade: React.FC<{ duration: number; children: React.ReactNode }> = ({
  duration,
  children,
}) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, 10, duration - 10, duration], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const scale = interpolate(frame, [0, duration], [1.015, 1]);
  return (
    <AbsoluteFill style={{ opacity, transform: `scale(${scale})`, fontFamily, color: color.text }}>
      {children}
    </AbsoluteFill>
  );
};

export const Headline: React.FC<{
  label: string;
  title: React.ReactNode;
  sub: string;
  width?: number;
}> = ({ label, title, sub, width = 720 }) => {
  const a = useEnter(2);
  const b = useEnter(8);
  const c = useEnter(16);
  const rise = (v: number) => ({ opacity: v, transform: `translateY(${(1 - v) * 28}px)` });
  return (
    <div style={{ position: "absolute", left: 140, top: 300, width }}>
      <div
        style={{
          ...rise(a),
          color: color.cyan,
          fontSize: 22,
          fontWeight: 700,
          letterSpacing: "0.18em",
        }}
      >
        {label}
      </div>
      <div
        style={{
          ...rise(b),
          marginTop: 22,
          fontSize: 92,
          fontWeight: 600,
          letterSpacing: "-0.055em",
          lineHeight: 0.98,
        }}
      >
        {title}
      </div>
      <div style={{ ...rise(c), marginTop: 30, color: color.muted, fontSize: 30, lineHeight: 1.45 }}>
        {sub}
      </div>
    </div>
  );
};

export const Card: React.FC<{ style?: React.CSSProperties; children: React.ReactNode }> = ({
  style,
  children,
}) => (
  <div
    style={{
      borderRadius: 28,
      border: `1px solid ${color.line}`,
      background: color.panel,
      boxShadow: "0 50px 110px rgba(0,0,0,0.45), inset 0 1px rgba(255,255,255,0.05)",
      ...style,
    }}
  >
    {children}
  </div>
);

export const Pill: React.FC<{ text: string; tint: string; style?: React.CSSProperties }> = ({
  text,
  tint,
  style,
}) => (
  <span
    style={{
      display: "inline-flex",
      alignItems: "center",
      padding: "8px 18px",
      borderRadius: 999,
      color: tint,
      background: `${tint}22`,
      fontSize: 22,
      fontWeight: 700,
      ...style,
    }}
  >
    {text}
  </span>
);

/** Characters revealed at `cps` per second starting at `start`. */
export const typed = (text: string, frame: number, start: number, cps = 40, fps = 30) =>
  text.slice(0, Math.max(0, Math.floor(((frame - start) / fps) * cps)));
