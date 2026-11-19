# planner-ai: the Calendar Planner's AI helper (R7)

Optional and **off**. Nothing reaches the model until all four steps below are done. The design is in `reports/zt-planner-design.md`, section 8.

What it does, for Plus accounts that switch it on in ZT Calendar:

- **Guess a task's length** from its title (and note). Needs the title, so "Hide titles" can't apply.
- **Turn one sentence into changes** from a fixed menu (`CHANGE_TYPES` in `planner_ai.ts`). The phone checks every change, shows it, and applies it only when the person confirms. The model never places blocks and never works out dates (it gets a table of days).

What is kept: per user and month, the number of requests, tokens and cost (`public.zt_ai_usage`). Never the text. The function doesn't log it.

Limits: 300 requests per user per month and a $20 monthly budget for everyone (both in `public.zt_ai_config`), checked before each request. Each request holds $0.005 of the budget while it runs (`reserve_usd`), swapped for its real cost when it ends, so requests running at the same time can't pass the budget together.

## Switching it on

1. **Run the test set first** (costs cents). With an Anthropic API key in `ANTHROPIC_API_KEY`:

   ```
   cd supabase/functions
   deno run --allow-env --allow-net --allow-read planner-ai/eval/run.ts
   deno run --allow-env --allow-net --allow-read planner-ai/eval/run.ts --model claude-sonnet-5-5
   ```

   Pass marks: 90% of requests fully correct, 80% of guesses in range, every trap safe. If Haiku 5.5 misses them, don't switch it on: see the design for the fallbacks.
2. **Apply the migration** `20261119190000_planner_ai.sql` (it creates the tables with `enabled = false`).
3. **Deploy the function and set the key:** `supabase functions deploy planner-ai` and `supabase secrets set ANTHROPIC_API_KEY=...`.
4. **Switch it on:** `update public.zt_ai_config set enabled = true;`

To switch it off again at any time: `update public.zt_ai_config set enabled = false;` The apps hide the helper on their next check.

Before it is offered to people, the privacy page and Play's data safety form must describe this optional sharing, and the provider's data retention terms should be checked.

## Files

- `index.ts`: the edge function (auth, plan and limits, the model call, counts).
- `planner_ai.ts`: inputs, the answer shapes, the prompts and the checks. Shared with the runner.
- `eval/cases.json`: 80 cases, half English and half Hebrew: 30 length guesses with an accepted range, 40 requests with the exact expected changes, 10 traps (unclear, impossible, and a task title that carries instructions).
- `eval/run.ts`, `eval/score.ts`: runs and scores the set.
- `planner_ai_test.ts`: unit tests without network (`deno test --allow-read planner-ai/`), run in CI.
