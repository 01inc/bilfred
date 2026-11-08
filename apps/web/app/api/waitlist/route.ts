import 'server-only';
import { createHmac } from 'node:crypto';
import { waitlistSchema } from '@/lib/waitlist-schema';
export const runtime = 'nodejs';

const reply = (data: object, status: number) => Response.json(data, {
  status, headers: { 'Cache-Control': 'no-store' },
});

export async function POST(request: Request) {
  if (request.headers.get('origin') !== new URL(request.url).origin) {
    return reply({ error: 'Åpne bilfred.com og prøv igjen.' }, 403);
  }
  if (!request.headers.get('content-type')?.startsWith('application/json')) {
    return reply({ error: 'Ugyldig forespørsel.' }, 415);
  }
  if (Number(request.headers.get('content-length') || 0) > 2048) {
    return reply({ error: 'Forespørselen er for stor.' }, 413);
  }
  const raw = await request.text();
  if (new TextEncoder().encode(raw).length > 2048) return reply({ error: 'Forespørselen er for stor.' }, 413);
  let json: unknown;
  try { json = JSON.parse(raw); } catch { return reply({ error: 'Ugyldig forespørsel.' }, 400); }
  const parsed = waitlistSchema.safeParse(json);
  if (!parsed.success) return reply({ error: 'Skriv inn en gyldig e-postadresse og gi samtykke.' }, 422);
  if (parsed.data.website) return reply({ accepted: true }, 202);
  const key = process.env.WAITLIST_API_KEY;
  const origin = process.env.BILFRED_API_BASE_URL;
  if (!key || !origin) return reply({ error: 'Ventelisten er midlertidig utilgjengelig. Prøv igjen snart.' }, 503);
  const client = request.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'local';
  const clientDigest = createHmac('sha256', key).update(`${new Date().toISOString().slice(0, 10)}:${client}`).digest('hex');
  try {
    const upstream = await fetch(new URL('/v1/waitlist', origin), {
      method: 'POST', redirect: 'error', cache: 'no-store', signal: AbortSignal.timeout(8000),
      headers: { 'Content-Type': 'application/json', 'X-Waitlist-Key': key },
      body: JSON.stringify({ email: parsed.data.email, consent: true, consent_version: parsed.data.consentVersion, client_digest: clientDigest }),
    });
    if (upstream.status === 429) return reply({ error: 'Du har prøvd flere ganger. Prøv igjen om en stund.' }, 429);
    if (!upstream.ok) return reply({ error: 'Vi kunne ikke lagre påmeldingen. Prøv igjen.' }, 503);
    return reply({ accepted: true }, 202);
  } catch {
    return reply({ error: 'Vi fikk ikke kontakt. Prøv igjen om et øyeblikk.' }, 503);
  }
}
