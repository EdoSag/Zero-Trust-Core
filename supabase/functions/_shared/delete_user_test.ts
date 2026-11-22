import { assertEquals, assertMatch, assertNotEquals } from "jsr:@std/assert@1";
import { hashToken, newToken } from "./delete_user.ts";
import { DELETION_HTML } from "./deletion_email.ts";

Deno.test("undo tokens are 43 base64url characters and differ", () => {
  const a = newToken(), b = newToken();
  assertMatch(a, /^[A-Za-z0-9_-]{43}$/);
  assertNotEquals(a, b);
});

Deno.test("token hash is SHA-256 as Postgres bytea hex", async () => {
  assertEquals(
    await hashToken("abc"),
    "\\xba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  );
});

Deno.test("the email has every placeholder, twice for the dates", () => {
  for (const p of ["{{DATE_EN}}", "{{DATE_HE}}", "{{UNDO_URL}}"]) {
    assertEquals(DELETION_HTML.includes(p), true, p);
  }
  assertEquals(DELETION_HTML.includes("{{ ."), false, "no Supabase template tags left");
});
