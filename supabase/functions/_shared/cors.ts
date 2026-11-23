// CORS for the functions the apps call with the user's session: the web
// builds call them from another origin, so the browser first sends an
// OPTIONS preflight and then needs these headers on every answer. The
// session travels in the Authorization header (never a cookie), so any
// origin may ask; without a valid session the function still refuses.
export const SESSION_CORS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "authorization, content-type, apikey, x-client-info",
  "access-control-max-age": "86400",
};

/** Answers preflights and adds [SESSION_CORS] to every response. */
export function withSessionCors(
  handler: (req: Request) => Response | Promise<Response>,
): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: SESSION_CORS });
    }
    const res = await handler(req);
    const headers = new Headers(res.headers);
    for (const [k, v] of Object.entries(SESSION_CORS)) headers.set(k, v);
    return new Response(res.body, { status: res.status, statusText: res.statusText, headers });
  };
}
