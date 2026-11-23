import { assertEquals } from "jsr:@std/assert@1";
import { withSessionCors } from "./cors.ts";

Deno.test("preflight is answered without calling the function", async () => {
  let called = false;
  const handler = withSessionCors(() => {
    called = true;
    return new Response("x");
  });
  const res = await handler(new Request("https://f/x", { method: "OPTIONS" }));
  assertEquals(res.status, 204);
  assertEquals(res.headers.get("access-control-allow-origin"), "*");
  assertEquals(called, false);
});

Deno.test("every answer carries the CORS headers", async () => {
  const handler = withSessionCors(() => new Response("Unauthorized", { status: 401 }));
  const res = await handler(new Request("https://f/x", { method: "POST" }));
  assertEquals(res.status, 401);
  assertEquals(await res.text(), "Unauthorized");
  assertEquals(
    res.headers.get("access-control-allow-headers"),
    "authorization, content-type, apikey, x-client-info",
  );
});
