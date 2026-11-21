#!/usr/bin/env python3
"""Build the PerformanceHUD website into dist/.

Standard library only, so the build never breaks because a dependency changed.
Run `python3 build.py` from this folder, then open dist/index.html or run
`python3 -m http.server -d dist` to preview.

- content/*.md   become /<name>/ pages (front matter: title, short, description,
                 layout: plain, include: path of a file to show instead of the body)
- pages/*.html   are page bodies written in HTML (index.html is the homepage)
- static/        is copied to the site root as-is (CSS, media, icons)

Every "/style.css" and "/media/..." URL in the pages gets ?v=<content hash>, so a changed file always reaches
visitors at a new URL even though static/_headers lets browsers keep media for 30 days.
"""
import hashlib
import html
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DIST = ROOT / "dist"
SITE = {
    "name": "PerformanceHUD",
    "url": "https://performancehud.com",
    "buy": "https://ko-fi.com/s/01a23ddc51",
    "github": "https://github.com/zzoko/PerformanceHUD",
    "price": "$3.99",
}
# Order of the documentation sidebar.
DOCS = ["install", "compatibility", "metalhud", "privacy", "changelog", "support", "license"]


# ---------------------------------------------------------------- Markdown

def slugify(text):
    text = re.sub(r"<[^>]+>", "", text).lower()
    return re.sub(r"[^a-z0-9]+", "-", text).strip("-")


def inline(text):
    """Escape a line, then apply links, code, bold and italic."""
    codes = []

    def keep_code(m):
        codes.append(f"<code>{html.escape(m.group(1))}</code>")
        return f"\x00{len(codes) - 1}\x00"

    text = re.sub(r"`([^`]+)`", keep_code, text)
    text = html.escape(text, quote=False)

    def link(m):
        label, href = m.group(1), m.group(2)
        external = href.startswith("http")
        attrs = ' rel="noopener"' if external else ""
        return f'<a href="{html.escape(href)}"{attrs}>{label}</a>'

    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", link, text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", text)
    return re.sub(r"\x00(\d+)\x00", lambda m: codes[int(m.group(1))], text)


def markdown(source):
    """Convert the Markdown subset used in content/ to HTML.

    Supports headings (with ids), paragraphs, bullet and numbered lists,
    links, `code`, **bold** and *italic*. Returns (html, headings).
    """
    out, headings, para, items, list_tag = [], [], [], [], None

    def flush_para():
        if para:
            out.append(f"<p>{inline(' '.join(para))}</p>")
            para.clear()

    def flush_list():
        nonlocal list_tag
        if items:
            out.append(f"<{list_tag}>" + "".join(f"<li>{inline(i)}</li>" for i in items) + f"</{list_tag}>")
            items.clear()
        list_tag = None

    for raw in source.splitlines():
        line = raw.rstrip()
        heading = re.match(r"^(#{2,4})\s+(.*)$", line)
        bullet = re.match(r"^[-*]\s+(.*)$", line)
        number = re.match(r"^\d+\.\s+(.*)$", line)
        if heading:
            flush_para(); flush_list()
            level, text = len(heading.group(1)), heading.group(2)
            hid = slugify(text)
            if level == 2:
                headings.append((hid, text))
            out.append(f'<h{level} id="{hid}">{inline(text)}</h{level}>')
        elif bullet or number:
            flush_para()
            tag = "ul" if bullet else "ol"
            if list_tag and list_tag != tag:
                flush_list()
            list_tag = tag
            items.append((bullet or number).group(1))
        elif not line.strip():
            flush_para(); flush_list()
        elif items and raw.startswith("  "):
            items[-1] += " " + line.strip()
        else:
            flush_list()
            para.append(line.strip())
    flush_para(); flush_list()
    return "\n".join(out), headings


def front_matter(text):
    meta = {}
    match = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if match:
        for line in match.group(1).splitlines():
            key, _, value = line.partition(":")
            meta[key.strip()] = value.strip()
        text = text[match.end():]
    return meta, text


# ---------------------------------------------------------------- Pages

def render(template, **values):
    return re.sub(r"\{\{(\w+)\}\}", lambda m: str(values.get(m.group(1), SITE.get(m.group(1), ""))), template)


def doc_nav(current, titles):
    links = []
    for slug in DOCS:
        here = ' aria-current="page"' if slug == current else ""
        links.append(f'<a href="/{slug}/"{here}>{html.escape(titles[slug])}</a>')
    return "\n".join(links)


VERSIONS = {}


def fingerprint(page):
    """Add ?v=<hash of the file's contents> to quoted /style.css and /media/ URLs that exist in dist/."""
    def versioned(m):
        url = m.group(1)
        file = DIST / url.lstrip("/")
        if not file.is_file():
            return m.group(0)
        if url not in VERSIONS:
            VERSIONS[url] = hashlib.sha256(file.read_bytes()).hexdigest()[:10]
        return f"{url}?v={VERSIONS[url]}"
    return re.sub(r'(?<=["\'])(/style\.css|/media/[^"\'?#\s]+)(?=["\'])', versioned, page)


def write(path, content):
    target = DIST / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(fingerprint(content))


def build():
    if DIST.exists():
        shutil.rmtree(DIST)
    shutil.copytree(ROOT / "static", DIST)
    layout = (ROOT / "templates/layout.html").read_text()
    doc_template = (ROOT / "templates/doc.html").read_text()

    docs = {}
    for file in sorted((ROOT / "content").glob("*.md")):
        meta, body = front_matter(file.read_text())
        if meta.get("include"):  # e.g. the license, kept in one place at the repo root
            body = (ROOT / meta["include"]).read_text()
        docs[file.stem] = (meta, body)
    titles = {slug: docs[slug][0].get("short", docs[slug][0]["title"]) for slug in DOCS}

    for slug, (meta, body) in docs.items():
        if meta.get("layout") == "plain":
            content, headings = f'<pre class="plain">{html.escape(body.strip())}</pre>', []
        else:
            content, headings = markdown(body)
        toc = "".join(f'<a href="#{hid}">{inline(text)}</a>' for hid, text in headings)
        main = render(doc_template, title=html.escape(meta["title"]), description=html.escape(meta.get("description", "")),
                      content=content, nav=doc_nav(slug, titles), toc=toc,
                      toc_class="" if len(headings) > 1 else " hidden", source=source_path(slug, meta))
        write(f"{slug}/index.html", render(layout, title=f"{meta['title']} · {SITE['name']}",
                                           description=html.escape(meta.get("description", "")),
                                           path=f"/{slug}/", main=main, body_class="doc"))

    for file in (ROOT / "pages").glob("*.html"):
        meta, body = front_matter(file.read_text())
        name = file.stem
        out = "index.html" if name == "index" else ("404.html" if name == "404" else f"{name}/index.html")
        page_path = "/" if name == "index" else f"/{name}/"
        title = meta.get("title", SITE["name"])
        write(out, render(layout, title=title, description=html.escape(meta.get("description", "")),
                          path=page_path, main=render(body), body_class=name))
    print(f"Built {len(docs)} docs and the homepage into {DIST.relative_to(ROOT)}/")


def source_path(slug, meta):
    """The file a visitor would edit on GitHub to change this page."""
    if meta.get("include"):
        return str((ROOT / meta["include"]).resolve().relative_to(ROOT.parent))
    return f"site/content/{slug}.md"


if __name__ == "__main__":
    build()
