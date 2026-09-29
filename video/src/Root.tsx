import { Composition } from "remotion";
import { Promo, PROMO_DURATION } from "./Promo";

export const Root = () => (
  <Composition
    id="LucidDiskPromo"
    component={Promo}
    durationInFrames={PROMO_DURATION}
    fps={30}
    width={1920}
    height={1080}
  />
);
