import { mkdir, readFile, writeFile, rename, chmod } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve, relative } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { schema, assessEnrichment } from './lib/workshop-enrichment.mjs';

// Engineering probe only: no application DB, no booking, no automatic bulk run.
try { process.loadEnvFile('.env'); } catch (e) { if (e.code !== 'ENOENT') throw e; }
if (!process.env.EXA_API_KEY) throw Error('EXA_API_KEY is required in the server environment');
const root = resolve('.local/verification/workshop-enrichment');
const singleExample = process.argv.includes('--tveita');
const argument = process.argv.slice(2).find(arg => !arg.startsWith('--'));
const output = argument ? resolve(argument) : resolve(root, new Date().toISOString().replaceAll(':', '-'));
if (!output.startsWith(`${root}/`)) throw Error('Receipts must stay under .local/verification/workshop-enrichment/');
await mkdir(output, { recursive: true, mode: 0o700 });
await chmod(output, 0o700);
const save = async (name, value) => {
  const path = resolve(output, name);
  await writeFile(`${path}.tmp`, JSON.stringify(value, null, 2) + '\n', { mode: 0o600 });
  await rename(`${path}.tmp`, path);
};
const load = async name => { try { return JSON.parse(await readFile(resolve(output, name), 'utf8')); } catch (e) { if (e.code === 'ENOENT') return null; throw e; } };

const registry = JSON.parse(await readFile('.local/verification/workshops/oslo-all.json', 'utf8'));
const selectedCases = singleExample ? [['28421', 'published_price_example']] : [
  ['1441', 'chain'], ['31906', 'membership_pricing'], ['1415', 'dealer'],
  ['33207', 'independent_missing_website'], ['1390', 'internal_workshop_negative_control'],
];
const cases = selectedCases.map(([id, scenario]) => {
  const r = registry.virksomheter.find(x => x.godkjenningsnr === id);
  if (!r) throw Error(`Missing pilot registry entity ${id}`);
  return { scenario, approval_id: id, organization_number: r.organisasjonsnr,
    name: r.orgNavn, address: r.besoksAdresse, postcode: r.besoksPostnummer,
    city: r.besoksPoststed, registry_website: r.internettAdresse,
    service_page: id === '28421' ? 'https://tveitabilservice.no/eu-kontroll/' : null,
    service: 'EU-kontroll', vehicle_scope: 'M1 passenger car up to 3500 kg; Skoda Superb; no membership assumed',
    area: { country: 'NO', county: '03', locality: 'Oslo' } };
});
const query = `Find this workshop branch's published EU-kontroll price in NOK and its review rating out of 5 with review count. Start with the supplied website and service page. Read the current live service page for the price rather than an older search snippet. Prefer the standard non-member price; preserve a from-price as from. Return the actual page URL supporting each value (including the actual publisher when reviews are republished). Use null for anything not found. Return schema_version 1.1 and the supplied approval_id. Do not research extra services, booking or availability. Do not contact anyone.`;

// 50 ms spacing caps this process at 20 requests/s, below the user's 25 QPS.
// Includes create, polls and retries. Pilot entities run simultaneously.
let nextRequest = 0;
const metrics = { requests: 0, throttles: 0 };
async function request(method, path, body) {
  const slot = Math.max(Date.now(), nextRequest); nextRequest = slot + 50;
  await sleep(Math.max(0, slot - Date.now())); metrics.requests++;
  const response = await fetch(`https://api.exa.ai${path}`, {
    method, headers: { Authorization: `Bearer ${process.env.EXA_API_KEY}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(45000), redirect: 'error',
  });
  const raw = await response.text();
  let data; try { data = JSON.parse(raw); } catch { data = { unparsed: raw }; }
  return { ok: response.ok, status: response.status, retryAfter: response.headers.get('retry-after'), data };
}
function retryDelay(value, attempt) {
  const seconds = Number(value);
  const parsed = value && !Number.isFinite(seconds) ? Date.parse(value) - Date.now() : seconds * 1000;
  return Math.max(1000, Number.isFinite(parsed) && parsed > 0 ? parsed : Math.min(30000, 1000 * 2 ** attempt));
}
async function run(entity) {
  const id = entity.approval_id; const started = Date.now();
  const payload = { query, input: { data: [entity] }, outputSchema: schema, effort: 'medium' };
  const inputHash = createHash('sha256').update(JSON.stringify(payload)).digest('hex');
  let checkpoint = await load(`${id}-checkpoint.json`);
  if (checkpoint && checkpoint.inputHash !== inputHash) throw Error(`Input changed for ${id}; use a new pilot directory`);
  if (checkpoint?.status === 'complete') return await load(`${id}-assessment.json`);
  if (checkpoint && !checkpoint.runId) throw Error(`Ambiguous start for ${id}; reconcile saved receipt before spending again`);
  if (!checkpoint) {
    await save(`${id}-request.json`, payload);
    checkpoint = { approvalId: id, scenario: entity.scenario, inputHash, startedAt: new Date().toISOString(), status: 'creating' };
    await save(`${id}-checkpoint.json`, checkpoint);
    let response;
    for (let attempt = 0; attempt < 6; attempt++) {
      response = await request('POST', '/agent/runs', payload);
      await save(`${id}-create-${attempt}.json`, response);
      if (response.status !== 429) break;
      metrics.throttles++; await sleep(retryDelay(response.retryAfter, attempt));
    }
    if (!response.ok || !response.data.id) {
      checkpoint.status = response.status >= 500 ? 'create_uncertain' : 'create_rejected';
      await save(`${id}-checkpoint.json`, checkpoint);
      return { approvalId: id, scenario: entity.scenario, status: checkpoint.status, httpStatus: response.status };
    }
    checkpoint.runId = response.data.id; checkpoint.status = response.data.status;
    await save(`${id}-checkpoint.json`, checkpoint);
    console.log(JSON.stringify({ event: 'started', approvalId: id, scenario: entity.scenario }));
  }
  const deadline = Date.now() + 12 * 60 * 1000;
  let previousStatus = checkpoint.status;
  while (Date.now() < deadline) {
    let response;
    try { response = await request('GET', `/agent/runs/${encodeURIComponent(checkpoint.runId)}`); }
    catch { await sleep(5000); continue; }
    if (!response.ok) {
      await save(`${id}-poll-error.json`, response);
      if (response.status === 429) { metrics.throttles++; await sleep(retryDelay(response.retryAfter, 3)); continue; }
      if (response.status >= 500) { await sleep(5000); continue; }
      return { approvalId: id, status: 'poll_failed', httpStatus: response.status };
    }
    const result = response.data;
    await save(`${id}-latest.json`, result);
    if (result.status !== previousStatus) {
      console.log(JSON.stringify({ event: 'status', approvalId: id, status: result.status })); previousStatus = result.status;
    }
    if (['completed', 'failed', 'cancelled'].includes(result.status)) {
      const assessment = { approvalId: id, name: entity.name, scenario: entity.scenario,
        status: result.status, stopReason: result.stopReason, elapsedSeconds: (Date.now() - started) / 1000,
        costDollars: result.costDollars, assessment: assessEnrichment(result.output?.structured, id, result.output?.grounding ?? []) };
      await save(`${id}-assessment.json`, assessment);
      await save(`${id}-checkpoint.json`, { ...checkpoint, status: 'complete', terminalStatus: result.status, completedAt: new Date().toISOString() });
      console.log(JSON.stringify({ event: 'complete', ...assessment })); return assessment;
    }
    await sleep(4000);
  }
  return { approvalId: id, status: 'waiting', runId: checkpoint.runId, resumeDirectory: relative(process.cwd(), output) };
}
await save('manifest.json', { schemaVersion: '1.1', promptVersion: '1.1', effort: 'medium', count: cases.length,
  activeJobs: cases.length, requestCeilingPerSecond: 20, userReportedQps: 25, plannedBaseCostDollars: cases.length * 0.1,
  registrySource: registry.sourceUrl, registryFetchedAt: registry.fetchedAt, cases });
console.log(JSON.stringify({ event: 'pilot', output: relative(process.cwd(), output), count: cases.length, concurrency: cases.length, plannedBaseCostDollars: cases.length * 0.1 }));
const outcomes = await Promise.allSettled(cases.map(run));
const results = outcomes.map((r, i) => r.status === 'fulfilled' ? r.value : ({ approvalId: cases[i].approval_id, status: 'probe_error', message: r.reason.message }));
await save('summary.json', { completedAt: new Date().toISOString(), metrics, results });
console.log(JSON.stringify({ event: 'summary', output: relative(process.cwd(), output), metrics, results }));
if (results.some(r => r.status !== 'completed')) process.exitCode = 1;
