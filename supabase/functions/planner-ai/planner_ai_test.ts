// Unit tests for the checks and the test set itself. No network:
//   deno test --allow-read planner-ai/
import {
  type Change,
  checkChanges,
  checkGuess,
  GuessInput,
  Input,
  RequestInput,
  requestMessage,
} from "./planner_ai.ts";
import { type Case, changesCorrect, type Expected, guessInRange, passes } from "./eval/score.ts";

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(msg);
}

const { cases } = JSON.parse(
  await Deno.readTextFile(new URL("./eval/cases.json", import.meta.url)),
) as { cases: Case[] };
const scenario = RequestInput.parse(cases.find((c) => c.kind === "request")!.input);

const empty: Change = {
  type: "ask",
  taskId: null,
  blockId: null,
  minutes: null,
  priority: null,
  date: null,
  start: null,
  end: null,
  title: null,
  weekday: null,
  hours: null,
  from: null,
  to: null,
  days: null,
  question: null,
  reason: null,
};
const change = (c: Partial<Change>): Change => ({ ...empty, ...c });

Deno.test("the test set: 80 cases, half Hebrew, and every expected answer passes the checks", () => {
  assert(cases.length === 80, `80 cases, got ${cases.length}`);
  const count = (f: (c: Case) => boolean) => cases.filter(f).length;
  assert(count((c) => c.kind === "guess") === 30, "30 guesses");
  assert(count((c) => c.kind === "request") === 40, "40 requests");
  assert(count((c) => c.kind === "trap") === 10, "10 traps");
  assert(count((c) => c.input.lang === "he") === 40, "40 in Hebrew");
  assert(new Set(cases.map((c) => c.id)).size === 80, "ids are unique");
  for (const c of cases) {
    const input = Input.parse(c.input);
    if (c.kind === "guess") continue;
    // An answer built from the expected changes must survive the checks,
    // or the case could never pass.
    const built = (c.expect as Expected[]).map((e) =>
      change({
        ...Object.fromEntries(
          Object.entries(e).filter(([k]) => k !== "startDate" && k !== "endDate"),
        ),
        type: e.type.split("|")[0] as Change["type"],
        title: e.type === "add_habit" ? "Habit" : null,
        question: e.type.startsWith("ask") ? "Which week?" : null,
        reason: e.type === "cannot" ? "Not possible" : null,
        start: (e.start as string) ?? (e.startDate ? `${e.startDate} 08:00` : null),
        end: (e.end as string) ?? (e.endDate ? `${e.endDate} 23:00` : null),
      })
    );
    const checked = checkChanges(input as RequestInput, { changes: built });
    assert(changesCorrect(c.expect as Expected[], checked), `${c.id} can pass`);
  }
});

Deno.test("changes with ids or dates not in the data are dropped", () => {
  const out = checkChanges(scenario, {
    changes: [
      change({ type: "set_length", taskId: "t-report", minutes: 300 }),
      change({ type: "set_length", taskId: "t-nope", minutes: 300 }),
      change({ type: "set_length", taskId: "t-bank", minutes: 0 }),
      change({ type: "lock", blockId: "b-nope" }),
      change({ type: "set_due", taskId: "t-tax", date: "2027-05-01" }),
      change({ type: "block_out", start: "2026-11-24 16:00", end: "2026-11-24 14:00" }),
      change({ type: "set_hours", weekday: 8, hours: "work", from: "09:00", to: "16:00" }),
      change({ type: "set_hours", weekday: 2, hours: "work", from: "25:00", to: "16:00" }),
      change({ type: "add_habit", title: " ", minutes: 30, days: [1], from: "12:00" }),
    ],
  });
  assert(out.length === 1 && out[0].taskId === "t-report", JSON.stringify(out));
});

Deno.test("a question stands alone; 'cannot' may come with changes", () => {
  const asked = checkChanges(scenario, {
    changes: [
      change({ type: "lock", blockId: "b-report-1" }),
      change({ type: "ask", question: "This week or next?" }),
    ],
  });
  assert(asked.length === 1 && asked[0].type === "ask", "only the question");
  const partly = checkChanges(scenario, {
    changes: [
      change({ type: "lock", blockId: "b-report-1" }),
      change({ type: "cannot", reason: "I can't invite people." }),
    ],
  });
  assert(partly.length === 2, "both kept");
});

Deno.test("guesses are rounded to 5 minutes and kept between 5 and 2400", () => {
  assert(checkGuess({ minutes: 47, confidence: "medium" })!.minutes === 45, "rounded");
  assert(checkGuess({ minutes: 1, confidence: "low" })!.minutes === 5, "at least 5");
  assert(checkGuess({ minutes: 99999, confidence: "low" })!.minutes === 2400, "at most 2400");
  assert(guessInRange({ min: 5, max: 20 }, 15), "in range");
  assert(!guessInRange({ min: 5, max: 20 }, null), "no answer is out of range");
});

Deno.test("inputs are bounded, and the sentence comes after the data", () => {
  let threw = false;
  try {
    GuessInput.parse({ job: "guess", lang: "en", title: "x".repeat(301), usualMinutes: 60 });
  } catch (_) {
    threw = true;
  }
  assert(threw, "long titles are refused");
  const text = requestMessage({ ...scenario, text: "Move everything" });
  assert(text.indexOf("</data>") < text.indexOf("<sentence>"), "data first");
});

Deno.test("pass marks", () => {
  const t = (r: number, g: number, s: number) => ({
    requests: { correct: r, total: 40 },
    guesses: { inRange: g, total: 30 },
    traps: { safe: s, total: 10 },
  });
  assert(passes(t(36, 24, 10)), "exactly at the marks");
  assert(!passes(t(35, 30, 10)), "requests below 90%");
  assert(!passes(t(40, 23, 10)), "guesses below 80%");
  assert(!passes(t(40, 30, 9)), "one unsafe trap fails");
});
