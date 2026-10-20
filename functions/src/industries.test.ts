import { test } from "node:test";
import assert from "node:assert/strict";
import { DEFAULT_INDUSTRIES, INDUSTRY_OTHER, allowedIndustries, cleanIndustries } from "./industries";

test("a stored list is trimmed, single-spaced and de-duplicated ignoring case", () => {
  assert.deepEqual(cleanIndustries(["  Garment   making ", "garment making", "Retail"]), ["Garment making", "Retail"]);
});

test("unusable entries are dropped and an unusable list is null", () => {
  assert.deepEqual(cleanIndustries(["Retail", 5, null, "", "   ", "<b>x</b>", "x".repeat(101)]), ["Retail"]);
  assert.equal(cleanIndustries([]), null);
  assert.equal(cleanIndustries(["", 7]), null);
  assert.equal(cleanIndustries("Retail"), null);
  assert.equal(cleanIndustries(undefined), null);
});

test("the list is capped at 50 entries", () => {
  const many = Array.from({ length: 80 }, (_, i) => `Industry ${i}`);
  assert.equal(cleanIndustries(many)?.length, 50);
});

test("no configured list means the defaults; 'Other' is always allowed", () => {
  assert.deepEqual(allowedIndustries(undefined), [...DEFAULT_INDUSTRIES]);
  assert.deepEqual(allowedIndustries(["Retail"]), ["Retail", INDUSTRY_OTHER]);
  assert.deepEqual(allowedIndustries(["Retail", "other"]), ["Retail", "other"]);
});

test("the defaults are themselves clean", () => {
  assert.deepEqual(cleanIndustries([...DEFAULT_INDUSTRIES]), [...DEFAULT_INDUSTRIES]);
});
