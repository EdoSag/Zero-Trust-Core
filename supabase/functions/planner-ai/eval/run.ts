// Runs the R7 test set against the model and prints the score and cost.
// Costs cents on Haiku 5.5. Needs ANTHROPIC_API_KEY.
//
//   deno run --allow-env --allow-net --allow-read eval/run.ts
//   deno run --allow-env --allow-net --allow-read eval/run.ts --model claude-sonnet-5-5
//   ... --only he   (one language)      ... --verbose   (every answer)
import Anthropic from "npm:@anthropic-ai/sdk@1.6.0";
import { zodOutputFormat } from "npm:@anthropic-ai/sdk@1.6.0/helpers/zod";
import {
  type Change,
  Changes,
  checkChanges,
  checkGuess,
  Guess,
  GUESS_SYSTEM,
  GuessInput,
  guessMessage,
  MODEL,
  REQUEST_SYSTEM,
  RequestInput,
  requestMessage,
} from "../planner_ai.ts";
import {
  type Case,
  changesCorrect,
  type Expected,
  guessInRange,
  passes,
  type Tally,
} from "./score.ts";

const args = Deno.args;
const flag = (name: string) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};
const model = flag("--model") ?? MODEL;
const only = flag("--only");
const verbose = args.includes("--verbose");

// Dollars per million tokens (input, output), for the cost line.
const PRICES: Record<string, [number, number]> = {
  "claude-haiku-5-5": [0.10, 0.50],
  "claude-sonnet-5-5": [2, 10],
};

const { cases } = JSON.parse(
  await Deno.readTextFile(new URL("./cases.json", import.meta.url)),
) as { cases: Case[] };
const client = new Anthropic({ maxRetries: 3 });
const tally: Tally = {
  requests: { correct: 0, total: 0 },
  guesses: { inRange: 0, total: 0 },
  traps: { safe: 0, total: 0 },
};
let inputTokens = 0, outputTokens = 0;
const failed: string[] = [];

for (const c of cases) {
  if (only && c.input.lang !== only) continue;
  let ok = false;
  let answer: unknown;
  try {
    if (c.kind === "guess") {
      tally.guesses.total++;
      const input = GuessInput.parse(c.input);
      const r = await client.messages.parse({
        model,
        max_tokens: 1024,
        system: GUESS_SYSTEM,
        output_config: { effort: "low", format: zodOutputFormat(Guess) },
        messages: [{ role: "user", content: guessMessage(input) }],
      });
      inputTokens += r.usage.input_tokens;
      outputTokens += r.usage.output_tokens;
      const g = r.stop_reason === "refusal" || !r.parsed_output
        ? null
        : checkGuess(r.parsed_output);
      answer = g;
      ok = guessInRange(c.expect as { min: number; max: number }, g?.minutes ?? null);
      if (ok) tally.guesses.inRange++;
    } else {
      const bucket = c.kind === "trap" ? tally.traps : tally.requests;
      bucket.total++;
      const input = RequestInput.parse(c.input);
      const r = await client.messages.parse({
        model,
        max_tokens: 4096,
        system: REQUEST_SYSTEM,
        output_config: { effort: "medium", format: zodOutputFormat(Changes) },
        messages: [{ role: "user", content: requestMessage(input) }],
      });
      inputTokens += r.usage.input_tokens;
      outputTokens += r.usage.output_tokens;
      const changes: Change[] = r.stop_reason === "refusal" || !r.parsed_output
        ? []
        : checkChanges(input, r.parsed_output);
      answer = changes.map((ch) =>
        Object.fromEntries(Object.entries(ch).filter(([, v]) => v != null))
      );
      ok = changesCorrect(c.expect as Expected[], changes);
      if (ok && c.kind === "trap") tally.traps.safe++;
      if (ok && c.kind === "request") tally.requests.correct++;
    }
  } catch (e) {
    answer = `error: ${(e as Error).message}`;
  }
  if (!ok) failed.push(c.id);
  if (verbose || !ok) {
    console.log(`${ok ? "ok  " : "FAIL"} ${c.id}: ${JSON.stringify(answer)}`);
  }
}

const [pin, pout] = PRICES[model] ?? [0, 0];
const cost = (inputTokens * pin + outputTokens * pout) / 1_000_000;
console.log(`\nModel ${model}${only ? ` (${only} only)` : ""}`);
console.log(`Requests fully correct: ${tally.requests.correct} of ${tally.requests.total}`);
console.log(`Guesses in range: ${tally.guesses.inRange} of ${tally.guesses.total}`);
console.log(`Traps handled safely: ${tally.traps.safe} of ${tally.traps.total}`);
console.log(`Tokens: ${inputTokens} in, ${outputTokens} out, about $${cost.toFixed(4)}`);
console.log(
  passes(tally) ? "PASSES the marks" : `Below the marks. Failed: ${failed.join(", ")}`,
);
Deno.exit(passes(tally) ? 0 : 1);
