import { assertEquals } from "jsr:@std/assert@1";
import { handoffToken } from "./handoff.ts";

const user = "7c0c3b9e-1f9c-4a43-9f43-5b0d7c1f2a11";
const hash = "a3f1c2d4e5b6a7980123456789abcdef0123456789abcdef01234567";

Deno.test("gives the token of a magic link for the same account", () => {
  assertEquals(
    handoffToken(user, { user: { id: user }, properties: { hashed_token: hash, verification_type: "magiclink" } }),
    { token_hash: hash, type: "magiclink" },
  );
});

Deno.test("a link without a type is a magic link", () => {
  assertEquals(handoffToken(user, { user: { id: user }, properties: { hashed_token: hash } })?.token_hash, hash);
});

Deno.test("refuses a link for another account", () => {
  assertEquals(
    handoffToken(user, { user: { id: "someone-else" }, properties: { hashed_token: hash } }),
    null,
  );
  assertEquals(handoffToken(user, { properties: { hashed_token: hash } }), null);
});

Deno.test("refuses other link types", () => {
  for (const type of ["recovery", "signup", "invite", "email_change"]) {
    assertEquals(
      handoffToken(user, { user: { id: user }, properties: { hashed_token: hash, verification_type: type } }),
      null,
    );
  }
});

Deno.test("refuses a missing or odd token", () => {
  for (const bad of [undefined, null, "", "short", "not hex at all, not hex at all!", "x".repeat(300)]) {
    assertEquals(
      handoffToken(user, { user: { id: user }, properties: { hashed_token: bad as string } }),
      null,
    );
  }
  assertEquals(handoffToken(user, null), null);
  assertEquals(handoffToken(user, { user: { id: user } }), null);
});
