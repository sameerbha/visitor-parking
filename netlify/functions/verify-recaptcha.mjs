// Verify reCAPTCHA
//
// Called from index.html's registration form before a registration is
// accepted. The checkbox widget alone only proves the browser rendered
// Google's widget — it doesn't prove anything about the specific token
// Google returned. This function holds the reCAPTCHA *secret* key
// server-side (it must never reach the browser) and asks Google directly
// whether a given token is genuine.
//
// Requires one environment variable set in Netlify's dashboard for this site
// (Site configuration -> Environment variables) — NOT in any file in this
// repo:
//   RECAPTCHA_SECRET_KEY   (from https://www.google.com/recaptcha/admin —
//                            the secret half of the site/secret key pair;
//                            the site key is public and lives in index.html)
//
// Also register these domains with Google when creating the key (reCAPTCHA
// v2, "I'm not a robot" checkbox): regentparking.ca (covers every
// *.regentparking.ca tenant subdomain automatically), dueastparking.netlify.app,
// and localhost (for local testing).

const ALLOWED_HOSTS = [
  /^localhost$/,
  /^127\.0\.0\.1$/,
  /^dueastparking\.netlify\.app$/,
  /^([a-z0-9-]+\.)?regentparking\.ca$/,
];

export default async (req) => {
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  const SECRET_KEY = process.env.RECAPTCHA_SECRET_KEY;
  if (!SECRET_KEY) {
    return json({ error: 'Server is missing RECAPTCHA_SECRET_KEY. Set it in Netlify -> Site configuration -> Environment variables, then redeploy.' }, 500);
  }

  let body;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid request body.' }, 400);
  }

  const token = (body.token || '').trim();
  if (!token) {
    return json({ success: false, error: 'Missing reCAPTCHA token.' }, 400);
  }

  let verifyRes;
  try {
    verifyRes = await fetch('https://www.google.com/recaptcha/api/siteverify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ secret: SECRET_KEY, response: token }),
    });
  } catch {
    return json({ success: false, error: 'Could not reach Google to verify the security check. Please try again.' }, 502);
  }

  const result = await verifyRes.json().catch(() => null);
  if (!result?.success) {
    return json({ success: false, error: 'Security check failed. Please try again.' }, 200);
  }

  // Defense in depth: reject tokens issued for a completely different site.
  // Google's own domain allowlist (set when the key is created) is the
  // primary control here — this just catches a token replayed from
  // somewhere unexpected onto this endpoint.
  const hostname = result.hostname || '';
  const hostOk = ALLOWED_HOSTS.some((re) => re.test(hostname));
  if (!hostOk) {
    return json({ success: false, error: 'Security check failed. Please try again.' }, 200);
  }

  return json({ success: true }, 200);
};

function json(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export const config = { path: '/api/verify-recaptcha' };
