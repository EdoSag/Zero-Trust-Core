import { assertEquals } from "jsr:@std/assert@1";
import { checkReport } from "./crash_report.ts";

const now = new Date("2026-11-22T12:00:00Z");
const good = {
  app: "notes",
  version: "0.4.1+12",
  platform: "android",
  day: "2026-11-22",
  type: "TypeError",
  message: "Null check operator used on a null value",
  uncaught: true,
  fingerprint: "0123456789abcdef",
  count: 2,
  frames: ["main (package:notes/main.dart:12:5)", "virt 2c3d4e"],
};

Deno.test("a scrubbed report passes unchanged", () => {
  assertEquals(checkReport(good, now), good);
});

Deno.test("count defaults to 1 and is capped", () => {
  const { count: _, ...noCount } = good;
  assertEquals(checkReport(noCount, now)?.count, 1);
  assertEquals(checkReport({ ...good, count: 5000 }, now)?.count, 1000);
  assertEquals(checkReport({ ...good, count: 0 }, now), null);
  assertEquals(checkReport({ ...good, count: 1.5 }, now), null);
});

Deno.test("extra fields are refused (no ids, emails, devices)", () => {
  assertEquals(checkReport({ ...good, email: "a@b.c" }, now), null);
  assertEquals(checkReport({ ...good, id: "x" }, now), null);
});

Deno.test("bad values are refused", () => {
  const bad: Record<string, unknown>[] = [
    { app: "Notes" },
    { app: "" },
    { version: "1.0 beta" },
    { platform: "symbian" },
    { type: "" },
    { type: "x".repeat(84) },
    { message: "x".repeat(164) },
    { message: "שלום" },
    { uncaught: "yes" },
    { fingerprint: "xyz" },
    { frames: Array(26).fill("f") },
    { frames: ["line\nbreak"] },
    { day: "2026-13-01" },
    { day: "2026-11-24" },
    { day: "2026-09-01" },
  ];
  for (const change of bad) {
    assertEquals(checkReport({ ...good, ...change }, now), null, JSON.stringify(change));
  }
  assertEquals(checkReport([], now), null);
  assertEquals(checkReport("x", now), null);
  assertEquals(checkReport(null, now), null);
});

Deno.test("yesterday and a day ahead (time zones) are fine", () => {
  assertEquals(checkReport({ ...good, day: "2026-11-21" }, now)?.day, "2026-11-21");
  assertEquals(checkReport({ ...good, day: "2026-11-23" }, now)?.day, "2026-11-23");
});
