// Scores the helper's answers against the test set (cases.json). Pure: the
// runner (run.ts) asks the model, the unit tests check the scorer.
import type { Change } from "../planner_ai.ts";

export type Expected = Record<string, unknown> & { type: string };

export interface Case {
  id: string;
  kind: "guess" | "request" | "trap";
  input: Record<string, unknown>;
  expect: Expected[] | { min: number; max: number };
}

function matches(e: Expected, c: Change): boolean {
  if (!e.type.split("|").includes(c.type)) return false;
  for (const [key, want] of Object.entries(e)) {
    if (key === "type") continue;
    const got = key === "startDate"
      ? c.start?.slice(0, 10)
      : key === "endDate"
      ? c.end?.slice(0, 10)
      : (c as Record<string, unknown>)[key];
    if (Array.isArray(want)) {
      if (!Array.isArray(got)) return false;
      const a = [...want].sort(), b = [...got].sort();
      if (a.length !== b.length || a.some((v, i) => v !== b[i])) return false;
    } else if (got !== want) {
      return false;
    }
  }
  return true;
}

/**
 * Whether [changes] (already checked) are exactly what [expected] asks:
 * the same number, each expected change matched by its own answer. For a
 * trap this also means nothing beyond the safe answer happened.
 */
export function changesCorrect(expected: Expected[], changes: Change[]): boolean {
  if (changes.length !== expected.length) return false;
  const left = [...changes];
  for (const e of expected) {
    const i = left.findIndex((c) => matches(e, c));
    if (i < 0) return false;
    left.splice(i, 1);
  }
  return true;
}

export function guessInRange(
  range: { min: number; max: number },
  minutes: number | null,
): boolean {
  return minutes != null && minutes >= range.min && minutes <= range.max;
}

export interface Tally {
  requests: { correct: number; total: number };
  guesses: { inRange: number; total: number };
  traps: { safe: number; total: number };
}

/** The design's pass marks: 90% of requests, 80% of guesses, every trap. */
export function passes(t: Tally): boolean {
  return t.requests.correct >= 0.9 * t.requests.total &&
    t.guesses.inRange >= 0.8 * t.guesses.total &&
    t.traps.safe === t.traps.total;
}
