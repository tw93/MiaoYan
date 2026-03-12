## Sponsor board workflow

This repo now keeps the sponsor wall data in two places (requires Node.js 18+):

1. `data/friends.json` – ordered list of everyone that has fed the cats.
2. `data/company-sponsors.json` – ordered list of company sponsors, each with a local logo path and display label.
3. `scripts/generate-sponsors.js` – turns the data + GitHub Sponsors API into `assets/sponsors.svg` and also refreshes the strings in `tailwind.css`.

### Manual update

1. Edit `data/friends.json`, keep one name per line.
2. Edit `data/company-sponsors.json` when a company sponsor is added or updated.
   - Store the logo asset in `assets/company-sponsors/`.
   - Prefer a symbol-only logo and let the script render the company name for better dark-mode contrast and layout consistency.
3. Run `npm run sponsors`.
   - This regenerates `assets/sponsors.svg` and updates the copy in `tailwind.css`.
4. Run `npm run build` so `build.css` stays in sync.
5. Commit the changes as usual.

### Automated daily build

The workflow in `.github/workflows/update-sponsors.yml` runs every day (and on demand) to refresh the SVG.  
Create a repo secret named `SPONSORS_TOKEN` that contains a personal access token with the `read:sponsorships`, `read:user`, and `read:org` scopes.  
If the token is missing the job still succeeds and reuses cached sponsor avatars from the existing SVG when available.  
If no cache exists yet, only the company sponsor section and friend list will be rendered.

For local development, the script also reads `~/.config/miaoyan/sponsors-token` when no environment variable is set.
The file may contain either the raw token or a line like `SPONSORS_TOKEN=github_pat_xxx`.

The generated SVG lives at `https://miaoyan.app/assets/sponsors.svg`, so it can be embedded anywhere that supports remote SVGs.
