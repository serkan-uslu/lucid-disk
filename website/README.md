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

- `public/media/lucid-disk-promo.mp4` and `promo-poster.jpg` come from `../video` (`npm run render`, then a web encode with `ffmpeg -crf 26 -movflags +faststart -an`).
- `public/shots/*.webp` come from the app's review harness with sample data: `LUCID_MARKETING=1 Tools/review_ui.sh -AppleLanguages '(en)' -AppleLocale en_US`, then `cwebp -q 86`.
- `public/brand/logo.webp` and `src/app/icon.png` are exports of `../Resources/AppIcon.png`.
- The download button points to `releases/latest/download/LucidDisk.dmg`, which the release workflow publishes.

## Deploy

Deploy on Vercel with **Root Directory** set to `website`. Set `NEXT_PUBLIC_SITE_URL` to the production URL so social previews use absolute links.

## License

Part of Lucid Disk, under the repository's [Apache License 2.0](../LICENSE).
