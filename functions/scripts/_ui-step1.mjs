import { Browser, seed, sleep } from "./_ui-drive.mjs";

const data = await seed();
const b = new Browser();
await b.start();
try {
  await b.open("http://127.0.0.1:8099/");
  await b.shot("01-login");
  console.log((await b.labels()).join("\n"));
} finally {
  b.stop();
  process.exit(0);
}
