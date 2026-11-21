# PerformanceHUD website

The source of performancehud.com. Plain HTML and CSS with a small build script that only uses Python's standard library, so there's nothing to install or keep updated.

## Folder layout

| Path | What it is |
| --- | --- |
| `content/*.md` | Documentation pages. Each file becomes `/<name>/`. |
| `pages/index.html` | The homepage, written in HTML. `pages/404.html` is the not-found page. |
| `templates/` | The shared page layout (`layout.html`) and the documentation layout (`doc.html`). |
| `static/` | Copied to the site as-is: `style.css`, `media/`, and Cloudflare's `_headers` and `_redirects`. `_headers` lets browsers keep `/media/` for 30 days, so the build adds `?v=<content hash>` to every `/style.css` and `/media/` URL in the pages: replace a file under the same name and visitors still get the new one. |
| `build.py` | Builds everything into `dist/` (not committed). |

`content/changelog.md` is also where the in-app update notes come from: `UpdateService/publish_update.py` reads the section for the version it's publishing. Add a `## v3.9` section at the top before releasing.

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
- **Sidebar order:** the `DOCS` list in `build.py`.
- **MacBook showcase:** a front view of the 14-inch MacBook Pro with PROLED XDR Display, drawn as SVG in two finishes (`static/media/macbook-pro-14-silver.svg` and `-space-black.svg`, both written by `tools/make_macbook_frames.py`; edit the script, not the SVGs). The frame sits over the screen video, `static/media/hero-screen-dark.mp4` or `hero-screen-light.mp4` (muted 20-second loops with the dark or light HUD), each with a `-poster.jpg` first frame; `.device-screen` in `style.css` matches the frame's transparent screen opening. The site is light by default (it ignores the system setting); the nav's dark mode button sets `:root[data-theme="dark"]` and is remembered per visitor. Light shows the silver finish, dark shows space black and the dark palette. The video follows the theme too: there's one `<video>` per theme (`data-theme-video`), only the current one loads at first, and on a switch the other starts at the same point in the loop and cross-fades in, so the HUD changes appearance mid-game. As the section scrolls in, its gray card widens to the full window and narrows again on the way out (script in `pages/index.html`); portrait screens, short windows and Reduce Motion get a plain card. Copy the videos and posters again from `MaintainerNotes/website-hero/out/final/` after a new render (`hero-dark.mp4` becomes `hero-screen-dark.mp4`, and so on).
- **Layouts band:** directly below the showcase, a closer look at the top of the same MacBook (`macbook-pro-14-top-*.svg`, the same drawing cropped by `tools/make_macbook_frames.py`), cut off by its card's bottom edge. Its screen plays `static/media/layouts-light.mp4` / `layouts-dark.mp4` (12-second loops of the menu switching the HUD layout, from `MaintainerNotes/website-hero/out/final/layouts-*.mp4`) with the same theme switching as the showcase; its videos load only once it's near the viewport.
- **Link preview:** `static/media/social-preview.jpg` (1200 × 630), the `og:image` for every page and the image to upload as the GitHub repository's social preview. `swift tools/make_social_image.swift` (run from `site/`) redraws it from the silver frame and the light hero poster; run it again after a new render.

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
