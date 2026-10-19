// Builds the Firebase Hosting folder: the public website at / and the app at /app/.
//
//   node scripts/build-hosting.mjs              website + Flutter web app
//   node scripts/build-hosting.mjs --site-only  website only (fast; for editing pages)
//
// Environment (all optional):
//   ENQUIRY_ENDPOINT  where the website forms post (default /api/enquiry, which
//                     firebase.json rewrites to the submitEnquiry function)
//   FLUTTER_ARGS      extra arguments for `flutter build web`
//
// Pages live in site/pages/*.html with a small front-matter block:
//   ---
//   title: Page title
//   description: One sentence for search results
//   ---
//   <section>...</section>
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const out = path.join(root, "hosting");
const siteOnly = process.argv.includes("--site-only");
const endpoint = process.env.ENQUIRY_ENDPOINT ?? "/api/enquiry";

const layout = readFileSync(path.join(root, "site", "layout.html"), "utf8");
const pagesDir = path.join(root, "site", "pages");

// Keep the previous app build when only the site is being rebuilt.
const keepApp = siteOnly && existsSync(path.join(out, "app"));
const appBackup = path.join(root, "build", "_app_backup");
if (keepApp) {
  rmSync(appBackup, { recursive: true, force: true });
  cpSync(path.join(out, "app"), appBackup, { recursive: true });
}
rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });
if (keepApp) {
  cpSync(appBackup, path.join(out, "app"), { recursive: true });
  rmSync(appBackup, { recursive: true, force: true });
}

cpSync(path.join(root, "site", "assets"), path.join(out, "assets"), { recursive: true });
cpSync(path.join(root, "web", "icons", "Icon-192.png"), path.join(out, "assets", "apple-touch-icon.png"));
writeFileSync(
  path.join(out, "assets", "config.js"),
  `window.HOLA_CONFIG = ${JSON.stringify({ enquiryEndpoint: endpoint, appUrl: "/app" })};\n`,
);

let connectSrc = "";
if (/^https?:\/\//.test(endpoint)) connectSrc = new URL(endpoint).origin;

function parse(file) {
  const raw = readFileSync(file, "utf8").replace(/\r\n/g, "\n");
  const match = raw.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) throw new Error(`${file}: missing front matter`);
  const meta = {};
  for (const line of match[1].split("\n")) {
    const i = line.indexOf(":");
    if (i > 0) meta[line.slice(0, i).trim()] = line.slice(i + 1).trim();
  }
  if (!meta.title || !meta.description) throw new Error(`${file}: title and description are required`);
  return { meta, body: match[2] };
}

const slugs = readdirSync(pagesDir).filter((f) => f.endsWith(".html")).map((f) => f.replace(/\.html$/, ""));
const escapeAttr = (s) => s.replace(/&/g, "&amp;").replace(/"/g, "&quot;");

for (const slug of slugs) {
  const { meta, body } = parse(path.join(pagesDir, `${slug}.html`));
  const isHome = slug === "index";
  const fullTitle = isHome ? meta.title : `${meta.title} | Hola Manje`;
  let html = layout
    .replaceAll("{{title}}", escapeAttr(fullTitle))
    .replaceAll("{{description}}", escapeAttr(meta.description))
    .replaceAll("{{slug}}", slug)
    .replaceAll("{{connectSrc}}", connectSrc)
    .replace("{{content}}", () => body);
  const current = isHome ? "home" : slug;
  html = html.replace(/\{\{cur:([a-z-]+)\}\}/g, (_, name) => (name === current ? ' aria-current="page"' : ""));
  html = html.replace("<html lang=\"en\">", "<html lang=\"en\" class=\"no-js\">");
  writeFileSync(path.join(out, isHome ? "index.html" : `${slug}.html`), html);
}
console.log(`site: ${slugs.length} pages -> hosting/`);

if (!siteOnly) {
  const args = ["build", "web", "--release", "--base-href", "/app/", "--output", path.join(out, "app"), ...(process.env.FLUTTER_ARGS ? process.env.FLUTTER_ARGS.split(" ") : [])];
  console.log(`flutter ${args.join(" ")}`);
  const r = spawnSync("flutter", args, { cwd: root, stdio: "inherit", shell: true });
  if (r.status !== 0) {
    console.error("flutter build failed");
    process.exit(r.status ?? 1);
  }
}
