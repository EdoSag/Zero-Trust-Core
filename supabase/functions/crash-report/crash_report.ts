// Checks one crash report from ZtHttpCrashReportSink (zero_trust_core) and
// returns exactly the fields the table keeps, or null when anything is off.
// The phone already scrubs reports; this refuses anything that could carry
// more than a scrubbed report does, so a modified client can't use the
// endpoint to store other data.

export type CrashReport = {
  app: string;
  version: string;
  platform: string;
  day: string;
  type: string;
  message?: string;
  library?: string;
  uncaught: boolean;
  fingerprint: string;
  count: number;
  frames: string[];
};

export const MAX_BODY_BYTES = 16 * 1024;
const PLATFORMS = new Set(["android", "ios", "web", "linux", "macos", "windows", "fuchsia"]);
const KEYS = new Set([
  "app", "version", "platform", "day", "type", "message", "library",
  "uncaught", "fingerprint", "count", "frames",
]);
// Printable ASCII only, as the phone's scrubber leaves it.
const PRINTABLE = /^[\x20-\x7e]*$/;
const DAY_MS = 24 * 60 * 60 * 1000;

const text = (v: unknown, max: number, pattern = PRINTABLE): v is string =>
  typeof v === "string" && v.length <= max && pattern.test(v);

/** [now] is injectable for tests. Reports up to 60 days old are accepted
 * (they can wait on the phone until the person sends them). */
export function checkReport(body: unknown, now = new Date()): CrashReport | null {
  if (typeof body !== "object" || body === null || Array.isArray(body)) return null;
  const r = body as Record<string, unknown>;
  for (const key of Object.keys(r)) if (!KEYS.has(key)) return null;

  if (!text(r.app, 24, /^[a-z_]{1,24}$/)) return null;
  if (!text(r.version ?? "", 40, /^[0-9A-Za-z.+_-]*$/)) return null;
  if (typeof r.platform !== "string" || !PLATFORMS.has(r.platform)) return null;
  if (!text(r.type, 83) || (r.type as string).length === 0) return null;
  if (r.message !== undefined && !text(r.message, 163)) return null;
  if (r.library !== undefined && !text(r.library, 63)) return null;
  if (typeof r.uncaught !== "boolean") return null;
  if (!text(r.fingerprint, 16, /^[0-9a-f]{16}$/)) return null;
  const count = r.count ?? 1;
  if (typeof count !== "number" || !Number.isInteger(count) || count < 1) return null;
  if (!Array.isArray(r.frames) || r.frames.length > 25) return null;
  for (const f of r.frames) if (!text(f, 400)) return null;

  if (!text(r.day, 10, /^\d{4}-\d{2}-\d{2}$/)) return null;
  const day = Date.parse(`${r.day}T00:00:00Z`);
  if (Number.isNaN(day)) return null;
  const today = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  if (day > today + DAY_MS || day < today - 60 * DAY_MS) return null;

  return {
    app: r.app as string,
    version: (r.version as string | undefined) ?? "",
    platform: r.platform,
    day: r.day as string,
    type: r.type as string,
    ...(r.message !== undefined ? { message: r.message as string } : {}),
    ...(r.library !== undefined ? { library: r.library as string } : {}),
    uncaught: r.uncaught,
    fingerprint: r.fingerprint as string,
    count: Math.min(count, 1000),
    frames: r.frames as string[],
  };
}
