import { Browser, seed, sleep } from "./_ui-drive.mjs";

const data = await seed();
const b = new Browser();
await b.start();
const all = async (tag) => { console.log(`--- ${tag}`); console.log([...new Set((await b.labels()).map((l) => l.replace(/\n/g, " | ")).filter((l) => !l.startsWith("-: EWA")))].join("\n")); };
try {
  await b.open("http://127.0.0.1:8099/");
  await b.fill(240, 484, data.admin.email);
  await b.fill(240, 546, data.admin.password);
  await b.click("Sign in", { exact: true });
  await sleep(4500);

  await b.click("More", { exact: true });
  await sleep(1000);
  await b.click("Payroll Export");
  await sleep(1500);
  await b.click("Run payroll");
  await sleep(800);
  await b.click("Run", { exact: true });
  await sleep(5000);
  await b.shot("10-payroll-runs");
  await all("payroll after run");

  await b.click("Net payout");
  await sleep(1200);
  await b.shot("11-payroll-expanded");
  await all("payroll expanded");

  await b.click("Create settlement");
  await sleep(3500);
  await b.shot("12-settlement-detail");
  await all("settlement detail");

  await b.click("Confirm payroll deductions");
  await sleep(1000);
  await b.shot("13-confirm-dialog");
  await b.fillBox(0, "375.00");
  await b.shot("14-confirm-filled");
  await b.click("Confirm", { exact: true });
  await sleep(2500);
  await b.shot("15-after-confirm");
  await all("settlement after confirm");
} catch (e) {
  console.log("ERROR", e.message);
  await b.shot("99-error");
  await all("error state");
} finally {
  b.stop();
  process.exit(0);
}
