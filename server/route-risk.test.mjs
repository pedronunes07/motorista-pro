import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateEvidence, assessRoute, localityHint } from './route-risk.mjs';
const now = 1_800_000_000_000;
const address = 'Rua de Teste, 1, Recife - PE';
const fixture = { status:'alert', country:'BR', matchedAddress:address, sourceName:'Fonte de teste (não real)', sourceUrl:'https://example.org/test-evidence', updatedAt:now-1000, expiresAt:now+1000, matchQuality:'exact', ambiguous:false };
test('only exact, dated, nonambiguous source evidence enables an alert', () => {
  assert.equal(validateEvidence(address,fixture,now).status,'alert');
  for (const changed of [{matchedAddress:'Outra rua'},{country:'US'},{sourceUrl:'http://example.org'},{updatedAt:now+1},{updatedAt:now-31*86400000},{expiresAt:now},{ambiguous:true},{matchQuality:'city'},{sourceName:''},{status:'safe'}]) {
    assert.equal(validateEvidence(address,{...fixture,...changed},now).status,'unknown');
  }
});
test('no source means unknown for every city, with no call to AI', async () => {
  const response=await assessRoute({country:'BR',pickup:address,destination:'Av. Teste, 2, Manaus - AM'}, {env:{OPENAI_API_KEY:'test',OPENAI_MODEL:'test'},fetcher:()=>{throw new Error('Unexpected call');}});
  assert.deepEqual(response,{pickup:{status:'unknown'},destination:{status:'unknown'}});
});
test('independent endpoints can have different coverage', async () => {
  const response=await assessRoute({country:'BR',pickup:address,destination:null}, {now,env:{RISK_PROVIDER_URL:'https://provider.example/risk'},fetcher:async()=>Response.json(fixture)});
  assert.equal(response.pickup.status,'alert'); assert.equal(response.destination.status,'unknown');
});
test('provider outage, malformed or truncated address never report safe', async () => {
  for (const pickup of [address,'Rua A…']) {
    const response=await assessRoute({country:'BR',pickup}, {env:{RISK_PROVIDER_URL:'https://provider.example/risk'},fetcher:async()=>{throw new Error('timeout');}});
    assert.equal(response.pickup.status,'unknown');
  }
});
test('AI cannot invent locality or assign risk', async () => {
  const env={OPENAI_API_KEY:'test',OPENAI_MODEL:'test'};
  const options=hint=>({env,fetcher:async()=>Response.json({output:[{content:[{type:'output_text',text:JSON.stringify(hint)}]}]})});
  assert.equal(await localityHint(address,options({city:'Salvador',state:'BA'})),null);
  assert.deepEqual(await localityHint(address,options({city:'Recife',state:'PE'})),{city:'Recife',state:'PE'});
});
