import { assert, assertEquals } from "jsr:@std/assert@1";
import { codeHash, isAuthSecret, isCode, newCode, normalizeEmail } from "./email_change.ts";
import { EMAIL_CHANGED_HTML, EMAIL_CODE_HTML } from "../_shared/email_change_email.ts";

Deno.test("emails are trimmed, lowercased and checked", () => {
  assertEquals(normalizeEmail("  Edo@Example.COM "), "edo@example.com");
  for (const bad of ["", "edo", "edo@", "@x.com", "a b@x.com", "edo@x", 5, null, "x".repeat(250) + "@x.com"]) {
    assertEquals(normalizeEmail(bad), null, String(bad));
  }
});

Deno.test("codes are 6 digits", () => {
  for (let i = 0; i < 200; i++) assert(isCode(newCode()));
  assert(!isCode("12345"));
  assert(!isCode("12345a"));
  assert(!isCode(123456));
});

Deno.test("auth secrets look like the app's HKDF output", () => {
  assert(isAuthSecret("A".repeat(43) + "="));
  assert(isAuthSecret("abc-_".repeat(8) + "abc"));
  assert(!isAuthSecret("short"));
  assert(!isAuthSecret("A".repeat(43) + "=="));
});

Deno.test("code hash depends on the user", async () => {
  const a = await codeHash("u1", "123456");
  assert(a.startsWith("\\x") && a.length === 66);
  assert(a !== await codeHash("u2", "123456"));
});

Deno.test("emails carry their placeholders", () => {
  assert(EMAIL_CODE_HTML.includes("{{CODE}}") && EMAIL_CODE_HTML.includes("{{NEW_EMAIL}}"));
  assert(EMAIL_CHANGED_HTML.includes("{{NEW_EMAIL}}") && !EMAIL_CHANGED_HTML.includes("{{CODE}}"));
});
