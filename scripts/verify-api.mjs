import assert from 'node:assert/strict';
import {mkdir, writeFile} from 'node:fs/promises';

try { process.loadEnvFile('.env'); } catch {}
const origin = process.argv[2] ?? 'http://127.0.0.1:8008';
async function request(path, {token, body, method} = {}) {
  const response = await fetch(new URL(path, origin), {
    method: method ?? (body === undefined ? 'GET' : 'POST'),
    headers: {'Content-Type':'application/json', ...(token ? {Authorization:`Bearer ${token}`} : {})},
    body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(25_000),
  });
  return {status:response.status, data:await response.json()};
}
const installation = await request('/v1/installations', {body:{}});
assert.equal(installation.status,201);
const token = installation.data.token;
const lookup = await request('/v1/vehicles/lookup',{token, body:{registration:'DEMO', demo:true}});
assert.equal(lookup.status,200);
const vehicle = lookup.data.vehicle_id;
assert.equal((await request(`/v1/vehicles/${vehicle}/mileage`,{token,body:{km:124239,observed_on:new Date().toISOString().slice(0,10)}})).status,201);
const home = await request(`/v1/vehicles/${vehicle}/home`,{token});
assert.equal(home.data.mileage.km,124239);
const searchBody = {vehicle_id:vehicle,service:'eu_kontroll',mode:'demo',area:{name:'Oslo',latitude:59.9139,longitude:10.7522,radius_km:15}};
const search = await request('/v1/service-searches',{token,body:searchBody});
assert.equal(search.data.options.length,3);
assert(search.data.options.every(o=>Number.isInteger(o.price_ore)&&o.price_ore>0&&o.rating>=0&&o.rating<=5));
const selected = search.data.options[1];
const offer = await request('/v1/offers',{token,body:{...searchBody,option_id:selected.id}});
assert.equal(offer.status,201);
assert.equal(offer.data.workshop.id,selected.id);
const acceptBody = {offer_version:offer.data.version,idempotency_key:crypto.randomUUID(),payment_method:'vipps'};
const accept = await request(`/v1/offers/${offer.data.id}/acceptances`,{token,body:acceptBody});
assert.equal(accept.status,200);
assert.equal(accept.data.status,'demo_accepted');
assert.deepEqual((await request(`/v1/offers/${offer.data.id}/acceptances`,{token,body:acceptBody})).data,accept.data);
assert.equal(accept.data.offer.payment_method,'vipps');
const bookings = await request('/v1/bookings',{token});
assert.equal(bookings.status,200);
const booking=bookings.data.bookings.find(x=>x.id===accept.data.id);
assert(booking && booking.state==='active');
const changedTime=new Date(Date.now()+30*86400_000).toISOString();
assert.equal((await request(`/v1/bookings/${booking.id}`,{token,method:'PATCH',body:{revision:booking.revision,appointment_at:changedTime}})).status,200);
const changed=(await request('/v1/bookings',{token})).data.bookings.find(x=>x.id===booking.id);
assert.equal(new Date(changed.appointment_at).getTime(),new Date(changedTime).getTime());
assert.deepEqual(changed.receipt,accept.data);
assert.equal((await request(`/v1/bookings/${booking.id}`,{token,method:'PATCH',body:{revision:changed.revision,state:'completed'}})).status,200);
const outsider = await request('/v1/installations',{body:{}});
assert.equal((await request(`/v1/vehicles/${vehicle}/home`,{token:outsider.data.token})).status,404);
let real = null;
if(process.env.VEGVESEN_TEST_REGISTRATION) {
  const actual = await request('/v1/vehicles/lookup',{token,body:{registration:process.env.VEGVESEN_TEST_REGISTRATION,demo:false}});
  assert.equal(actual.status,200);
  assert.equal(actual.data.facts.demo,false);
  assert.equal(actual.data.facts.source,'Statens vegvesen');
  real = {eu_due_on:actual.data.facts.eu_due_on,cache_state:actual.data.facts.cache_state,source_retrieved_at:actual.data.facts.fetched_at};
  const research = await request(`/v1/vehicles/${actual.data.vehicle_id}/research`,{token,body:{}});
  assert.equal(research.status,200);
  const actualHome = await request(`/v1/vehicles/${actual.data.vehicle_id}/home`,{token});
  assert.equal(actualHome.status,200);
  assert.equal(actualHome.data.timeline.find(x=>x.id==='eu_kontroll').due_on,actual.data.facts.eu_due_on);
  real.maintenance_status=research.data.status;
  real.timeline_events=actualHome.data.timeline.length;
}
const report={verified_at:new Date().toISOString(),origin,journey:'passed',options:3,acceptance_replay:'same_receipt',ownership:'outsider_denied',payment_selection:'vipps',history:'rescheduled_and_completed',original_offer:'unchanged',real_vehicle:real};
await mkdir('.local/verification',{recursive:true});
await writeFile('.local/verification/api-journey.json',JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));
