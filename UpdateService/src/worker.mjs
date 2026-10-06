import releases from "./releases.json" with { type: "json" };

const HEADER = "X-PerformanceHUD-Updater";
const TTL = 10 * 60;
const encoder = new TextEncoder();
const filenamePattern = /^PerformanceHUD-[A-Za-z0-9._-]+\.zip$/;

const home = `<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PerformanceHUD updates</title>
<style>body{font:17px system-ui;max-width:36rem;margin:15vh auto;padding:24px;color-scheme:light dark;line-height:1.6}a{color:#579bdd}</style>
<h1>PerformanceHUD</h1><p>Already have the app? Use <strong>Check for updates</strong> in its menu.</p>
<p>Get your first copy from <a href="https://ko-fi.com/s/01a23ddc51">Ko-fi</a>, or
<a href="https://github.com/zzoko/PerformanceHUD">build it from source</a>.</p></html>`;

function response(body, status = 200, extra = {}) {
  return new Response(body, { status, headers: {
    "Cache-Control": "private, no-store",
    "X-Content-Type-Options": "nosniff",
    "X-Robots-Tag": "noindex, nofollow",
    "Referrer-Policy": "no-referrer",
    ...extra
  } });
}

function base64url(bytes) {
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function decode(value) {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new Error("Invalid ticket encoding");
  return Uint8Array.from(atob(value.replaceAll("-", "+").replaceAll("_", "/")), c => c.charCodeAt(0));
}

async function key(secret) {
  if (typeof secret !== "string" || secret.length < 32) throw new Error("Missing download signing secret");
  return crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

async function ticket(secret, payload) {
  const data = base64url(encoder.encode(JSON.stringify(payload)));
  const signature = await crypto.subtle.sign("HMAC", await key(secret), encoder.encode(data));
  return `${data}.${base64url(new Uint8Array(signature))}`;
}

async function validTicket(secret, value, file, host, now) {
  try {
    if (!value || value.length > 2048) return false;
    const parts = value.split(".");
    if (parts.length !== 2) return false;
    const [data, signature] = parts;
    if (!await crypto.subtle.verify("HMAC", await key(secret), decode(signature), encoder.encode(data))) return false;
    const p = JSON.parse(new TextDecoder().decode(decode(data)));
    return p.file === file && p.host === host && typeof p.nonce === "string"
      && Number.isInteger(p.iat) && Number.isInteger(p.exp)
      && p.iat <= now && p.exp > now && p.exp - p.iat === TTL;
  } catch { return false; }
}

// Assets never fall through to public serving. Every route, including raw asset
// paths and preview URLs, must pass through this handler (run_worker_first: true).
export function createHandler(published, clock = () => Math.floor(Date.now() / 1000)) {
  const files = new Set(published.map(r => r.file).filter(f => filenamePattern.test(f)));
  return {
    async fetch(request, env) {
      const url = new URL(request.url);
      if (request.method !== "GET" && request.method !== "HEAD") return response("Method not allowed", 405, { Allow: "GET, HEAD" });
      const head = request.method === "HEAD";
      if (url.pathname === "/") return response(head ? null : home, 200, {
        "Content-Type": "text/html; charset=utf-8",
        "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'"
      });
      if (url.pathname === "/robots.txt") return response(head ? null : "User-agent: *\nDisallow: /\n");
      // Check the updater request marker before serving update resources.
      if (request.headers.get(HEADER) !== "1") return response(head ? null : "Use Check for updates inside PerformanceHUD.", 403);
      if (url.pathname === "/appcast.xml") {
        const asset = await env.ASSETS.fetch(new Request(new URL("/appcast.xml", url), { method: request.method }));
        if (!asset.ok) return response(head ? null : "Updates temporarily unavailable", 503);
        return response(head ? null : asset.body, 200, { "Content-Type": "application/xml; charset=utf-8" });
      }
      const match = /^\/(download|archive)\/(PerformanceHUD-[A-Za-z0-9._-]+\.zip)$/.exec(url.pathname);
      if (!match || !files.has(match[2])) return response(head ? null : "Not found", 404);
      const [, route, file] = match;
      if (typeof env.DOWNLOAD_SIGNING_SECRET !== "string" || env.DOWNLOAD_SIGNING_SECRET.length < 32) {
        return response(head ? null : "Downloads temporarily unavailable", 503);
      }
      if (route === "download") {
        // Mint only at download time, never when the appcast is checked. Redirect
        // stays on the same origin so Sparkle keeps the updater header.
        const now = clock();
        const token = await ticket(env.DOWNLOAD_SIGNING_SECRET,
          { file, host: url.host, iat: now, exp: now + TTL, nonce: crypto.randomUUID() });
        return response(null, 302, { Location: `/archive/${file}?ticket=${encodeURIComponent(token)}` });
      }
      if (!await validTicket(env.DOWNLOAD_SIGNING_SECRET, url.searchParams.get("ticket"), file, url.host, clock())) {
        return response(head ? null : "Download permission expired. Check for updates again in the app.", 403);
      }
      // Only registered packages are readable; client URLs cannot select arbitrary assets.
      // Preserve Range for resumable/retried downloads during the ten-minute session.
      const headers = new Headers();
      for (const name of ["Range", "If-Range"]) {
        if (request.headers.has(name)) headers.set(name, request.headers.get(name));
      }
      const asset = await env.ASSETS.fetch(new Request(new URL(`/packages/${file}`, url), { method: request.method, headers }));
      if (asset.status !== 200 && asset.status !== 206 && asset.status !== 416) return response(null, 503);
      const downloadHeaders = { "Content-Type": "application/zip", "Content-Disposition": `attachment; filename="${file}"` };
      for (const name of ["Content-Length", "Content-Range", "Accept-Ranges", "ETag", "Last-Modified"]) {
        if (asset.headers.has(name)) downloadHeaders[name] = asset.headers.get(name);
      }
      return response(head ? null : asset.body, asset.status, downloadHeaders);
    }
  };
}

export default createHandler(releases);
