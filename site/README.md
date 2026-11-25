# PerformanceHUD website

The source of performancehud.com. Plain HTML and CSS with a small build script that only uses Python's standard library, so there's nothing to install or keep updated.

## Folder layout

| Path | What it is |
| --- | --- |
| `content/*.md` | Documentation pages. Each file becomes `/<name>/`. |
| `pages/index.html` | The homepage, written in HTML. `pages/404.html` is the not-found page. |
| `templates/` | The shared page layout (`layout.html`) and the documentation layout (`doc.html`). |
| `static/` | Copied to the site as-is: `style.css`, `media/`, and Cloudflare's `_headers` and `_redirects`. `_headers` lets browsers keep `/media/` for 30 days, so the build adds `?v=<content hash>` to every `/style.css` and `/media/` URL in the pages, including the link-preview image's full address: replace a file under the same name and visitors still get the new one. |
| `build.py` | Builds everything into `dist/` (not committed). |

`content/changelog.md` is also where the in-app update notes come from: `UpdateService/publish_update.py` reads the section for the version it's publishing. Add a `## X.Y` section for the new version at the top before each release.

`content/license.md` shows the repository's `LICENSE` file, so the license only exists in one place.

## Preview locally

```sh
cd site
python3 build.py
python3 -m http.server 8000 -d dist
```

Then open http://localhost:8000.

## Editing

- **Doc pages:** edit the Markdown in `content/`. Supported: `##`/`###` headings (they get link anchors automatically), paragraphs, bullet and numbered lists, links, `code`, **bold** and *italic*. Front matter sets `title`, an optional shorter `short` title for the sidebar, and `description`.
- **Homepage:** edit `pages/index.html`. `{{buy}}`, `{{price}}` and `{{github}}` are filled in from `SITE` at the top of `build.py`, so the price and links only need changing there.
- **Placeholders in doc pages:** the same `SITE` values work in `content/*.md`, plus `{{version}}`: the newest `## X.Y` heading in `content/changelog.md`, which is also the newest release tag. The Install page's clone command uses it, so it follows each release without edits. Anything in `{{…}}` that isn't a `SITE` name is left as written.
- **Sidebar order:** the `DOCS` list in `build.py`.
- **MacBook showcase:** a front view of the 14-inch MacBook Pro with PROLED XDR Display, drawn as SVG in two finishes (`static/media/macbook-pro-14-silver.svg` and `-space-black.svg`, both written by `tools/make_macbook_frames.py`; edit the script, not the SVGs). The frame sits over one screen video, `static/media/hero-screen.mp4` (a muted 20-second loop: the dark HUD on the Pro Black desktop, then three games), with `hero-screen-poster.jpg` as its first frame; `.device-screen` in `style.css` matches the frame's transparent screen opening. The site is light by default (it ignores the system setting); the nav's dark mode button sets `:root[data-theme="dark"]` and is remembered per visitor. Light shows the silver finish, dark shows space black and the dark palette; the video is the same in both. As the section scrolls in, its gray card widens to the full window and narrows again on the way out (script in `pages/index.html`); portrait screens, short windows and Reduce Motion get a plain card, and with Reduce Motion only the poster shows. The finished hero renders for each wallpaper are kept in `MaintainerNotes/website-hero/renders/`: to change the hero, copy one in under these two names and redraw the link preview.
- **HUD explorer:** the first thing in Features & controls. It shows the HUD alone in its three presets (`static/media/hud-<preset>.webp`, and `hud-<preset>-fps.webp` with the frame rate rolled in: stills of the dark HUD from `MaintainerNotes/website-hero`, the same in both themes) beside a short note per row. A preset button swaps the still; pointing at a note or a row outlines that part; the FPS still shows while the FPS note is selected (script in `pages/index.html`). The sizes and row positions live in the page's `explorer-data` block: after a new explorer render, run `python3 tools/explorer_data.py ../MaintainerNotes/website-hero/out/final/hud-explorer.json` to update them. Without scripts it's the Balanced HUD and a plain list.
- **Link preview:** `static/media/social-preview.jpg` (1200 × 630), the `og:image` for every page and the image to upload as the GitHub repository's social preview. `swift tools/make_social_image.swift` (run from `site/`) redraws it from the silver frame and the hero poster; run it again after a new hero.

## Deploying on Cloudflare Pages

One-time setup in the Cloudflare dashboard, under **Workers & Pages → Create → Pages → Connect to Git**:

1. Choose the `zzoko/PerformanceHUD` repository and the `main` branch.
2. Build settings:
   - **Framework preset:** None
   - **Build command:** `python3 build.py`
   - **Build output directory:** `dist`
   - **Root directory:** `site`
3. Under **Build watch paths**, include `site/*` and `LICENSE`, so app-only commits don't redeploy the site.
4. Deploy. The site appears at `<project>.pages.dev` straight away.
5. When the domain is bought, add it under **Custom domains**.

After that, every push to `main` that touches the site deploys automatically, and other branches get their own preview addresses.
