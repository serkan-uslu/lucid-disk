import { Audio } from "@remotion/media";
import { AbsoluteFill, interpolate, Sequence, staticFile } from "remotion";
import { Background, SceneFade } from "./components";
import { AIScene } from "./scenes/AIScene";
import { Intro } from "./scenes/Intro";
import { MapScene } from "./scenes/MapScene";
import { MCPScene } from "./scenes/MCPScene";
import { Outro } from "./scenes/Outro";
import { ReviewScene } from "./scenes/ReviewScene";

// 30 seconds at 30 fps. AI and MCP get the longest beats.
const scenes = [
  { id: "intro", duration: 90, Component: Intro },
  { id: "map", duration: 150, Component: MapScene },
  { id: "review", duration: 150, Component: ReviewScene },
  { id: "ai", duration: 210, Component: AIScene },
  { id: "mcp", duration: 195, Component: MCPScene },
  { id: "outro", duration: 105, Component: Outro },
];

export const PROMO_DURATION = scenes.reduce((sum, scene) => sum + scene.duration, 0);

export const Promo = () => {
  let from = 0;
  return (
    <AbsoluteFill>
      <Audio
        src={staticFile("audio/glassy-pulse.mp3")}
        volume={(frame) =>
          interpolate(frame, [0, 45, 840, PROMO_DURATION - 1], [0, 0.8, 0.8, 0], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          })
        }
      />
      <Background />
      {scenes.map(({ id, duration, Component }) => {
        const start = from;
        from += duration;
        return (
          <Sequence key={id} from={start} durationInFrames={duration} name={id}>
            <SceneFade duration={duration}>
              <Component />
            </SceneFade>
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};
