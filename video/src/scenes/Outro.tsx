import { Img, staticFile } from "remotion";
import { useEnter } from "../components";
import { color, monoFamily } from "../theme";

export const Outro = () => {
  const icon = useEnter(0, 14);
  const title = useEnter(8);
  const meta = useEnter(18);
  const url = useEnter(26);
  const rise = (v: number) => ({ opacity: v, transform: `translateY(${(1 - v) * 24}px)` });
  return (
    <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center" }}>
      <Img
        src={staticFile("app-icon.png")}
        style={{ width: 170, height: 170, opacity: icon, transform: `scale(${0.7 + icon * 0.3})`, filter: "drop-shadow(0 0 40px rgba(77,211,227,0.5))" }}
      />
      <div style={{ ...rise(title), marginTop: 40, fontSize: 104, fontWeight: 600, letterSpacing: "-0.06em" }}>Lucid Disk</div>
      <div style={{ ...rise(meta), marginTop: 8, fontSize: 32, color: color.muted }}>
        Open source · macOS 14+ · Apache 2.0
      </div>
      <div
        style={{
          ...rise(url),
          marginTop: 44,
          padding: "18px 34px",
          borderRadius: 16,
          background: color.cyan,
          color: color.ink,
          fontFamily: monoFamily,
          fontSize: 30,
          fontWeight: 600,
        }}
      >
        github.com/serkan-uslu/lucid-disk
      </div>
    </div>
  );
};
