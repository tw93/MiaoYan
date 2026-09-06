# MiaoYan Website Agent Guide

This is the website checkout on the `vercel` branch. The app source and its Xcode commands live on a different branch.

- `index.html`, `privacy.html`, `assets/`, and `data/` contain site content; `vercel.json` owns redirects.
- `tailwind.css` is the source for `build.css`; rebuild with `npm run build` after stylesheet edits.
- `appcast.xml` and `Release/` are distribution surfaces. Changes need the actual published version, download, and artifact verified; do not infer release success from XML syntax alone.
- `npm run sponsors` invokes a network-backed generator, not a read-only verifier. Read its inputs and output paths before running it.
- Check local links for documentation edits and render affected pages for visual changes. Preserve unrelated site work and stable asset URLs.
