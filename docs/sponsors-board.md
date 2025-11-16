## Sponsor board workflow

This repo now keeps the sponsor wall data in two places (requires Node.js 18+):

1. `data/friends.json` – ordered list of everyone that has fed the cats.
2. `scripts/generate-sponsors.js` – turns the data + GitHub Sponsors API into `assets/sponsors.svg` and also refreshes the strings in `tailwind.css`.

### Manual update

1. Edit `data/friends.json`, keep one name per line.
2. Run `npm run sponsors`.
   - This regenerates `assets/sponsors.svg` and updates the copy in `tailwind.css`.
3. Run `npm run build` so `build.css` stays in sync.
4. Commit the changes as usual.

### Automated daily build

The workflow in `.github/workflows/update-sponsors.yml` runs every day (and on demand) to refresh the SVG.  
Create a repo secret named `SPONSORS_TOKEN` that contains a personal access token with the `read:sponsorships`, `read:user`, and `read:org` scopes.  
If the token is missing the job still succeeds but only the friend list will be rendered (no GitHub avatars).

The generated SVG lives at `https://miaoyan.app/assets/sponsors.svg`, so it can be embedded anywhere that supports remote SVGs.
