import test from "node:test";
import assert from "node:assert/strict";
import { createHandler } from "../src/worker.mjs";

const file = "PerformanceHUD-2.0-8.zip";
const other = "PerformanceHUD-2.1-9.zip";
const base = "https://updates.example.test";
const header = { "X-PerformanceHUD-Updater": "1" };
const archive = new TextEncoder().encode("signed test package");

function fixture() {
  let time = 1000;
  const reads = [];
  const env = {
    DOWNLOAD_SIGNING_SECRET: "test-only-key-not-used-for-any-deployment-1234567890",
    ASSETS: { async fetch(request) {
      const path = new URL(request.url).pathname;
      reads.push({ path, range: request.headers.get("Range") });
      if (path === "/appcast.xml") return new Response("<rss>signed feed bytes</rss>");
      if (path === `/packages/${file}` || path === `/packages/${other}`) {
        const ranged = request.headers.has("Range");
        return new Response(request.method === "HEAD" ? null : (ranged ? archive.slice(0, 3) : archive), {
          status: ranged ? 206 : 200,
          headers: ranged ? { "Content-Range": `bytes 0-2/${archive.length}`, "Content-Length": "3" } : { "Content-Length": String(archive.length) }
        });
      }
      return new Response("Not found", { status: 404 });
    } }
  };
  const handler = createHandler([{ file }, { file: other }], () => time);
  const fetch = (path, headers = header, method = "GET") => handler.fetch(new Request(new URL(path, base), { method, headers }), env);
  return { fetch, reads, env, advance: n => { time += n; } };
}

test("normal browser visitors get acquisition instructions, never a package", async () => {
  const f = fixture();
  const home = await f.fetch("/", {});
  assert.match(await home.text(), /ko-fi.com/);
  for (const route of ["/appcast.xml", `/download/${file}`, `/archive/${file}`, `/packages/${file}`]) {
    assert.equal((await f.fetch(route, {})).status, 403);
  }
  assert.equal(f.reads.length, 0);
});

test("the signed feed is served unchanged and never cached publicly", async () => {
  const f = fixture();
  const r = await f.fetch("/appcast.xml?ignored=query");
  assert.equal(r.status, 200);
  assert.equal(await r.text(), "<rss>signed feed bytes</rss>");
  assert.match(r.headers.get("Cache-Control"), /no-store/);
  assert.deepEqual(f.reads.map(r => r.path), ["/appcast.xml"]);
});

test("download mints a same-origin ticket and requires the protocol header to redeem it", async () => {
  const f = fixture();
  const start = await f.fetch(`/download/${file}`);
  assert.equal(start.status, 302);
  const link = start.headers.get("Location");
  assert.ok(link.startsWith(`/archive/${file}?ticket=`));
  assert.equal(f.reads.length, 0);
  assert.equal((await f.fetch(link, {})).status, 403);
  const r = await f.fetch(link);
  assert.equal(r.status, 200);
  assert.deepEqual(new Uint8Array(await r.arrayBuffer()), archive);
  assert.match(r.headers.get("Cache-Control"), /no-store/);
  assert.equal((await f.fetch(link, { ...header, Range: "bytes=0-2" })).status, 206);
  assert.equal(f.reads.at(-1).range, "bytes=0-2");
});

test("tickets expire after ten minutes, with retries valid before expiry", async () => {
  const f = fixture();
  const link = (await f.fetch(`/download/${file}`)).headers.get("Location");
  f.advance(599);
  assert.equal((await f.fetch(link)).status, 200);
  f.advance(1);
  assert.equal((await f.fetch(link)).status, 403);
  const next = (await f.fetch(`/download/${file}`)).headers.get("Location");
  assert.notEqual(next, link);
  assert.equal((await f.fetch(next)).status, 200);
});

test("changing ticket contents, archive, or origin does not grant access", async () => {
  const f = fixture();
  const link = (await f.fetch(`/download/${file}`)).headers.get("Location");
  assert.equal((await f.fetch(link.replace(file, other))).status, 403);
  assert.equal((await f.fetch(`https://another.example.test${link}`)).status, 403);
  const url = new URL(link, base);
  const [payload, signature] = url.searchParams.get("ticket").split(".");
  const p = JSON.parse(Buffer.from(payload, "base64url"));
  p.exp += 6000;
  url.searchParams.set("ticket", Buffer.from(JSON.stringify(p)).toString("base64url") + "." + signature);
  assert.equal((await f.fetch(url.toString())).status, 403);
  for (const invalid of ["bad", "a.b.c", "!!!.???", "x".repeat(2050)]) {
    url.searchParams.set("ticket", invalid);
    assert.equal((await f.fetch(url.toString())).status, 403);
  }
});

test("raw assets, unknown releases, method changes and encoded paths fail closed", async () => {
  const f = fixture();
  for (const path of [`/packages/${file}`, `/download/PerformanceHUD-unknown.zip`, `/download/%2e%2e%2f${file}`, `/archive/${file}`, "/_headers", "/index.html"]) {
    assert.ok([403, 404].includes((await f.fetch(path)).status));
  }
  assert.equal((await f.fetch(`/download/${file}`, header, "POST")).status, 405);
  assert.equal((await f.fetch(`/download/${file}`, header, "OPTIONS")).status, 405);
  assert.equal(f.reads.length, 0);
});

test("missing secrets or packages cannot expose static assets", async () => {
  const f = fixture();
  f.env.DOWNLOAD_SIGNING_SECRET = "";
  assert.equal((await f.fetch(`/download/${file}`)).status, 503);
  assert.equal(f.reads.length, 0);
  f.env.ASSETS.fetch = async () => new Response(null, { status: 404 });
  assert.equal((await f.fetch("/appcast.xml")).status, 503);
});

test("HEAD responses carry no body, including protected downloads", async () => {
  const f = fixture();
  const link = (await f.fetch(`/download/${file}`)).headers.get("Location");
  for (const path of ["/", "/robots.txt", "/appcast.xml", link]) {
    const r = await f.fetch(path, header, "HEAD");
    assert.equal(r.status, 200);
    assert.equal(await r.text(), "");
  }
});
