import { Browser, seed, sleep } from "./_ui-drive.mjs";

const data = await seed();
const b = new Browser();
await b.start();
try {
  await b.open("http://127.0.0.1:8099/");
  await b.fill(240, 484, data.admin.email);
  await b.fill(240, 546, data.admin.password);
  await b.click("Sign in", { exact: true });
  await sleep(4500);
  await b.shot("02-admin-home");
  await b.dump("admin home");

  await b.click("More", { exact: true });
  await sleep(1000);
  await b.shot("03-more");
  await b.dump("more");

  await b.click("Payroll Export");
  await sleep(1500);
  await b.click("Run payroll");
  await sleep(800);
  await b.dump("run dialog");
  await b.click("Run", { exact: true });
  await sleep(5000);
  await b.shot("05-payroll-run");
  await b.dump("after run");
} catch (e) {
  console.log("ERROR", e.message);
  await b.shot("99-error");
  await b.dump("error state");
} finally {
  b.stop();
  process.exit(0);
}
