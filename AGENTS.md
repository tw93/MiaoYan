# MiaoYan Website Agent Guide

This is the website checkout on the `vercel` branch. The app source and its Xcode commands live on a different branch.

- `index.html`, `privacy.html`, `assets/`, and `data/` contain site content; `vercel.json` owns redirects.
- `scripts/build-site.py` generates the home pages `index.html` (English) and `zh/index.html` from one copy table; edit it and run `python3 -I scripts/build-site.py` instead of editing those two files. They use `site.css`, whose tokens follow mole.fit.
- The site recommends the App Store and links only to the App Store and the GitHub repository, never to a Mac download (maintainer, 2026-10-11). Store links carry `data-store`: iPhone and iPad get the region-less link, which opens the App Store app, the Mac gets `macappstore://`, and other devices keep the default, `/cn/` on the Chinese page because a desktop browser in China loses the app on the region-less link.
- `tailwind.css` is the source for `build.css`, which `cats.html` still uses; rebuild with `npm run build` after stylesheet edits.
- `appcast.xml` and `Release/` are distribution surfaces. Changes need the actual published version, download, and artifact verified; do not infer release success from XML syntax alone.
- `npm run sponsors` invokes a network-backed generator, not a read-only verifier. Read its inputs and output paths before running it.
- Check local links for documentation edits and render affected pages for visual changes. Preserve unrelated site work and stable asset URLs.
