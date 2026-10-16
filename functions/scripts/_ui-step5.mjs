import { Browser, seed, sleep } from "./_ui-drive.mjs";

const data = await seed();
const b = new Browser();
await b.start();
try {
  await b.login("http://127.0.0.1:8099/", data.admin.email, data.admin.password);
  await b.click("More", { exact: true });
  await sleep(1000);
  const tiles = [
    ["Full activity and decision history", "40-audit-log"],
    ["Standard hourly rates", "41-rate-matrix"],
    ["Draw caps, fees", "42-settings"],
    ["Configure what each role", "43-permissions"],
    ["Add, remove and reorder", "44-org-config"],
    ["Review and sign off attendance", "45-signoff"],
  ];
  for (const [text, shot] of tiles) {
    await b.click(text);
    await sleep(2200);
    await b.shot(shot);
    await b.click("Back", { exact: true });
    await sleep(900);
  }
  console.log("done");
} catch (e) {
  console.log("ERROR", e.message);
  await b.shot("97-error");
} finally {
  b.stop();
  process.exit(0);
}
