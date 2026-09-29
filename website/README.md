# Lucid Disk website

The landing page for [Lucid Disk](https://github.com/serkan-uslu/lucid-disk): a single static Next.js page with the promo video, real app screenshots, and the download link.

## Develop

```bash
npm install
npm run dev        # http://localhost:3002
npm run lint
npm run build
```

## Content sources

- `public/media/lucid-disk-promo.mp4` and `promo-poster.jpg` come from `../video` (`npm run render`, then a web encode that preserves the soundtrack: `ffmpeg -i out/lucid-disk-promo.mp4 -map 0:v:0 -map 0:a:0 -c:v libx264 -crf 26 -preset medium -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart out/lucid-disk-promo-web.mp4`).
- `public/shots/*.webp` come from the app's review harness with sample data: `LUCID_MARKETING=1 Tools/review_ui.sh -AppleLanguages '(en)' -AppleLocale en_US`, then `cwebp -q 86`.
- `public/brand/logo.webp` and `src/app/icon.png` are exports of `../Resources/AppIcon.png`.
- The download button points to `releases/latest/download/LucidDisk.dmg`, which the release workflow publishes.

## Deploy

Live at https://lucid-disk.vercel.app. The Vercel project `lucid-disk` is connected to this repository with **Root Directory** `website`: pushes to `main` deploy production and pull requests get preview deployments. For a manual production deploy, run `npx vercel deploy --prod` from the repository root. Set `NEXT_PUBLIC_SITE_URL` to the production URL so social previews use absolute links.

## License

Part of Lucid Disk, under the repository's [Apache License 2.0](../LICENSE).
