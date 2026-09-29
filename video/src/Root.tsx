import { Composition, Still } from "remotion";
import { Gallery, galleryItems } from "./Gallery";
import { Promo, PROMO_DURATION } from "./Promo";

export const Root = () => (
  <>
    <Composition
      id="LucidDiskPromo"
      component={Promo}
      durationInFrames={PROMO_DURATION}
      fps={30}
      width={1920}
      height={1080}
    />
    {/* Product Hunt gallery images (1270×760). */}
    {galleryItems.map(({ id, ...props }) => (
      <Still key={id} id={id} component={Gallery} width={1270} height={760} defaultProps={props} />
    ))}
  </>
);
