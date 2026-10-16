// TEMPORARY dev tool: drives the web build (served on :8099, built with
// --dart-define=USE_EMULATORS=true) in headless Chrome over the DevTools
// protocol, against the emulators. Not part of the repo's tooling.
import { spawn } from "node:child_process";
import { writeFileSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
process.env.GCLOUD_PROJECT ??= "demo-ewa-test";
const OUT = process.env.UI_OUT;
const CHROME = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
const PORT = 9333;

initializeApp({ projectId: "demo-ewa-test" });
const db = getFirestore();
const auth = getAuth();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const hex = (n = 3) => randomBytes(n).toString("hex");

export async function seed() {
  const co = db.collection("companies").doc();
  const shortCode = `U${hex(3).toUpperCase()}`;
  await co.set({ name: "UI Test Co", shortCode, currency: "SZL", active: true });
  await db.collection("company_codes").doc(shortCode).set({ companyId: co.id });
  await co.collection("settings").doc("app").set({
    companyName: "UI Test Co", maxDrawPercent: 0.5, feePercent: 0.05, maxDrawsPerCycle: 2,
    paydayRule: { type: "lastDayOfMonth", dayOfMonth: 25, weekday: 5 },
  });
  const mk = async (email, claims, doc) => {
    const password = randomBytes(10).toString("hex");
    const u = await auth.createUser({ email, password });
    await auth.setCustomUserClaims(u.uid, claims);
    await co.collection("employees").doc(u.uid).set({ ...doc, active: true, consentedAt: Timestamp.now(), mustChangePassword: false });
    return { uid: u.uid, email, password };
  };
  const admin = await mk(`ui.admin.${hex()}@example.test`, { companyId: co.id, platformAdmin: false }, { name: "Admin User", role: "admin", hourlyRate: 0, employeeNumber: "A1" });
  const workers = [];
  for (const [name, total] of [["Alice Dlamini", 10500], ["Bongani Nkosi", 12000], ["Cebile Simelane", 20000]]) {
    const w = await mk(`ui.w.${hex()}@example.test`, { companyId: co.id, platformAdmin: false }, { name, role: "worker", hourlyRate: 50, employeeNumber: `W${hex(1)}` });
    const now = Date.now();
    await co.collection("time_sessions").add({ employeeId: w.uid, clockInTs: Timestamp.fromMillis(now - 4 * 3_600_000), clockOutTs: Timestamp.fromMillis(now - 3_600_000) });
    const amount = Math.round(total / 1.05);
    await co.collection("draw_requests").add({ employeeId: w.uid, amountMinor: amount, feeMinor: total - amount, totalMinor: total, status: "approved", createdAt: Timestamp.now(), payrollRunId: null, disbursementStatus: "completed" });
    workers.push({ ...w, name });
  }
  const platformPassword = randomBytes(10).toString("hex");
  const platform = await auth.createUser({ email: `ui.platform.${hex()}@example.test`, password: platformPassword });
  await auth.setCustomUserClaims(platform.uid, { platformAdmin: true });
  return { co, shortCode, admin, workers, platform: { uid: platform.uid, email: platform.email, password: platformPassword } };
}

export class Browser {
  async start() {
    this.proc = spawn(CHROME, [
      "--headless=new", `--remote-debugging-port=${PORT}`, `--user-data-dir=${OUT}\\prof-${hex()}`,
      "--window-size=480,900", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
      "--no-first-run", "about:blank",
    ], { stdio: "ignore" });
    let targets;
    for (let i = 0; i < 40; i++) {
      try { targets = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json(); if (targets.some((t) => t.type === "page")) break; } catch {}
      await sleep(500);
    }
    const page = targets.find((t) => t.type === "page");
    this.ws = new WebSocket(page.webSocketDebuggerUrl);
    await new Promise((r) => (this.ws.onopen = r));
    this.id = 0; this.pending = new Map();
    this.ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && this.pending.has(d.id)) { this.pending.get(d.id)(d); this.pending.delete(d.id); } };
    await this.send("Page.enable"); await this.send("Runtime.enable");
    await this.send("Emulation.setDeviceMetricsOverride", { width: 480, height: 900, deviceScaleFactor: 1, mobile: false });
  }
  send(method, params = {}) { return new Promise((res) => { const id = ++this.id; this.pending.set(id, res); this.ws.send(JSON.stringify({ id, method, params })); }); }
  async eval(expr) { const r = await this.send("Runtime.evaluate", { expression: expr, returnByValue: true, awaitPromise: true }); return r.result?.result?.value; }
  async open(url) {
    await this.send("Page.navigate", { url });
    for (let i = 0; i < 60; i++) { if (await this.eval("!!document.querySelector('flt-glass-pane')")) break; await sleep(500); }
    await sleep(2500);
    await this.eval("document.querySelector('flt-semantics-placeholder')?.click()");
    await sleep(1000);
  }
  async nodes() {
    return JSON.parse(await this.eval(`JSON.stringify([...document.querySelectorAll('flt-semantics')].map(e => { const r = e.getBoundingClientRect(); const label = e.getAttribute('aria-label') || e.textContent || ''; return { label: label.trim().slice(0,120), role: e.getAttribute('role') || '', x: Math.round(r.x + r.width/2), y: Math.round(r.y + r.height/2), w: Math.round(r.width), h: Math.round(r.height) }; }).filter(n => n.label && n.w > 0 && n.h > 0))`)) ?? [];
  }
  async find(text, { exact = false } = {}) {
    const t = text.toLowerCase();
    for (let i = 0; i < 20; i++) {
      const matches = (await this.nodes()).filter((n) => (exact ? n.label.toLowerCase() === t : n.label.toLowerCase().includes(t)));
      matches.sort((a, b) => a.w * a.h - b.w * b.h);
      if (matches.length) return matches[0];
      await sleep(500);
    }
    return null;
  }
  async clickAt(x, y) {
    for (const type of ["mousePressed", "mouseReleased"]) await this.send("Input.dispatchMouseEvent", { type, x, y, button: "left", clickCount: 1 });
    await sleep(700);
  }
  async click(text, opts) { const n = await this.find(text, opts); if (!n) throw new Error(`not found: ${text}`); await this.clickAt(n.x, n.y); return n; }
  async type(label, value) { const n = await this.find(label); if (!n) throw new Error(`field not found: ${label}`); await this.clickAt(n.x, n.y); await sleep(300); await this.send("Input.insertText", { text: value }); await sleep(300); }
  async shot(name) { const r = await this.send("Page.captureScreenshot", { format: "png" }); writeFileSync(`${OUT}\\${name}.png`, Buffer.from(r.result.data, "base64")); }
  async labels() { return (await this.nodes()).map((n) => `${n.role || "-"}: ${n.label}`); }
  async dump(tag) {
    const lines = (await this.labels()).filter((l) => !l.includes("\n") && l.length < 90 && !l.startsWith("-: EWA"));
    console.log(`--- ${tag}\n${[...new Set(lines)].join("\n")}`);
  }
  async login(url, email, password) {
    for (let attempt = 1; attempt <= 4; attempt++) {
      await this.open(url);
      await this.fill(240, 484, email);
      await this.fill(240, 546, password);
      await this.click("Sign in", { exact: true });
      await sleep(4500);
      const failed = (await this.nodes()).some((n) => n.label.includes("Incorrect email or password") || n.label.includes("Sign in to your account"));
      if (!failed) return;
      console.log(`login attempt ${attempt} did not get through, retrying`);
    }
    throw new Error("login failed after 4 attempts");
  }
  async textboxes() {
    const all = JSON.parse(await this.eval(`JSON.stringify([...document.querySelectorAll('flt-semantics[role="textbox"], flt-semantics input, flt-semantics textarea')].map(e => { const r = e.getBoundingClientRect(); return { label: (e.getAttribute('aria-label') || e.closest('flt-semantics')?.getAttribute('aria-label') || '').slice(0,80), x: Math.round(r.x + r.width/2), y: Math.round(r.y + r.height/2), w: Math.round(r.width), h: Math.round(r.height) }; }).filter(n => n.w > 0 && n.h > 0))`)) ?? [];
    return all.sort((a, b) => a.y - b.y);
  }
  async fillBox(index, text) { const t = await this.textboxes(); if (!t[index]) throw new Error(`no textbox #${index}`); await this.fill(t[index].x, t[index].y, text); }
  async fill(x, y, text) { await this.clickAt(x, y); await sleep(600); await this.send("Input.insertText", { text }); await sleep(600); }
  stop() { try { this.ws.close(); } catch {} this.proc?.kill(); }
}

export { sleep };
