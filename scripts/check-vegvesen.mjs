import { mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
if (existsSync(join(root, '.env'))) process.loadEnvFile(join(root, '.env'));
const out = join(root, '.local/verification');
mkdirSync(out, { recursive: true, mode: 0o700 });
const origin = 'https://akfell-datautlevering.atlas.vegvesen.no';
const receipt = { checkedAt: new Date().toISOString(), checks: [] };

async function check(kind, path, headers = {}) {
  const started = performance.now();
  try {
    const response = await fetch(new URL(path, origin), {
      headers, redirect: 'error', signal: AbortSignal.timeout(12000),
    });
    const body = await response.text();
    const result = { kind, status: response.status, durationMs: Math.round(performance.now() - started) };
    if (kind === 'authenticated-vehicle') {
      // Private response only: never print registrations, VINs, or provider bodies.
      writeFileSync(join(out, 'vegvesen-last-response.txt'), body, { mode: 0o600 });
      if (response.status === 200) {
        try {
          const data = JSON.parse(body);
          result.vehicleCount = Array.isArray(data.kjoretoydataListe) ? data.kjoretoydataListe.length : 0;
          result.lookupVerified = result.vehicleCount === 1;
          if (result.lookupVerified) {
            writeFileSync(join(out, 'vegvesen-vehicle-response.txt'), body, { mode: 0o600 });
            writeFileSync(join(out, 'vegvesen-vehicle-source.json'), JSON.stringify({
              fetchedAt: new Date().toISOString(), provider: 'Statens vegvesen',
              endpoint: '/enkeltoppslag/kjoretoydata', schemaVersion: 1,
            }, null, 2) + '\n', { mode: 0o600 });
          }
        } catch { result.lookupVerified = false; }
      } else result.lookupVerified = false;
    }
    receipt.checks.push(result);
    console.log(JSON.stringify(result));
    return result;
  } catch (error) {
    const result = { kind, error: error.name, durationMs: Math.round(performance.now() - started) };
    receipt.checks.push(result);
    console.log(JSON.stringify(result));
    return result;
  }
}

await check('public-documentation', '/swagger-ui/index.html');
await check('authentication-boundary', '/enkeltoppslag/kjoretoydata');
const key = process.env.VEGVESEN_API_KEY?.trim();
const registration = process.env.VEGVESEN_TEST_REGISTRATION?.replace(/\s/g, '').toUpperCase();
if (key && registration) {
  const result = await check('authenticated-vehicle',
    `/enkeltoppslag/kjoretoydata?${new URLSearchParams({ kjennemerke: registration })}`,
    { 'SVV-Authorization': `Apikey ${key}`, Accept: 'application/json' });
  if (!result.lookupVerified) process.exitCode = 1;
} else {
  receipt.authenticatedLookup = 'pending-local-configuration';
  console.log('Authenticated lookup pending: set both private .env values.');
}
writeFileSync(join(out, 'vegvesen-check.json'), JSON.stringify(receipt, null, 2) + '\n', { mode: 0o600 });
