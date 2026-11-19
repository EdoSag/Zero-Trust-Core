// The Calendar Planner's AI helper (R7). OFF unless the owner switches it
// on (public.zt_ai_config.enabled) and sets the ANTHROPIC_API_KEY secret.
//
// POST {job: "guess", ...} or {job: "request", ...} (see planner_ai.ts)
// with the user's session token. Checks the plan and the limits, asks the
// model, checks the answer and returns it. Stores only counts (requests,
// tokens, cost); never logs or stores the text.
import Anthropic from "npm:@anthropic-ai/sdk@1.6.0";
import { zodOutputFormat } from "npm:@anthropic-ai/sdk@1.6.0/helpers/zod";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  Changes,
  checkChanges,
  checkGuess,
  Guess,
  GUESS_SYSTEM,
  guessMessage,
  Input,
  MODEL,
  REQUEST_SYSTEM,
  requestMessage,
} from "./planner_ai.ts";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const jwt = req.headers.get("Authorization")?.replace("Bearer ", "");
  if (!jwt) return json({ error: "unauthorized" }, 401);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: { user }, error } = await admin.auth.getUser(jwt);
  if (error || !user) return json({ error: "unauthorized" }, 401);

  let input: Input;
  try {
    input = Input.parse(await req.json());
  } catch (_) {
    return json({ error: "bad_input" }, 400);
  }

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) return json({ error: "off" }, 503);

  // Counts the request (or says why not) before anything is sent.
  const { data: verdict, error: takeError } = await admin.rpc(
    "zt_ai_take_request",
    { p_user: user.id },
  );
  if (takeError) return json({ error: "server" }, 500);
  if (verdict !== "ok") return json({ error: verdict }, verdict === "off" ? 503 : 429);

  // A failure here must not lose the answer the person already has.
  const record = (usage: { input_tokens: number; output_tokens: number }) =>
    admin.rpc("zt_ai_record_tokens", {
      p_user: user.id,
      p_input: usage.input_tokens,
      p_output: usage.output_tokens,
    }).then(() => {}, () => {});

  const client = new Anthropic({ apiKey, maxRetries: 1, timeout: 30_000 });
  try {
    if (input.job === "guess") {
      const response = await client.messages.parse({
        model: MODEL,
        max_tokens: 1024,
        system: GUESS_SYSTEM,
        output_config: { effort: "low", format: zodOutputFormat(Guess) },
        messages: [{ role: "user", content: guessMessage(input) }],
      });
      await record(response.usage);
      if (response.stop_reason === "refusal") return json({ error: "refused" }, 422);
      const guess = response.parsed_output ? checkGuess(response.parsed_output) : null;
      if (!guess) return json({ error: "no_answer" }, 502);
      return json({ guess });
    }
    const response = await client.messages.parse({
      model: MODEL,
      max_tokens: 4096,
      system: REQUEST_SYSTEM,
      output_config: { effort: "medium", format: zodOutputFormat(Changes) },
      messages: [{ role: "user", content: requestMessage(input) }],
    });
    await record(response.usage);
    if (response.stop_reason === "refusal") return json({ error: "refused" }, 422);
    if (!response.parsed_output) return json({ error: "no_answer" }, 502);
    return json({ changes: checkChanges(input, response.parsed_output) });
  } catch (e) {
    if (e instanceof Anthropic.RateLimitError) return json({ error: "busy" }, 503);
    if (e instanceof Anthropic.APIError) return json({ error: "provider" }, 502);
    return json({ error: "server" }, 500);
  }
});

