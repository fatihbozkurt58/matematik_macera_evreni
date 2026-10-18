import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';

// Explicit fixed dev target. Temporary synthetic data and debug allowlist entry
// are removed in finally. No access token, password, or App Check token is logged.
const projectId = 'matematik-evreni-dev';
process.env.GOOGLE_CLOUD_QUOTA_PROJECT = projectId;
const appId = '1:1086662773964:android:429cd8d2400e93844fc669';
const appPath = `projects/1086662773964/apps/${appId}`;
if (process.argv.length !== 3 || !['--apply','--cleanup-only'].includes(process.argv[2])) {
  console.log('Dry run: verify deployed dev Auth/Functions/App Check/Rules with temporary synthetic data; use --apply.');
  process.exit(0);
}
for (const key of ['FIREBASE_AUTH_EMULATOR_HOST', 'FIRESTORE_EMULATOR_HOST']) assert.equal(process.env[key], undefined);
const accessToken = execFileSync('gcloud', ['auth', 'print-access-token', '--quiet'], {encoding:'utf8'}).trim();
assert.ok(accessToken);
const require = createRequire(new URL('../functions/package.json', import.meta.url));
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
initializeApp({projectId, credential:{getAccessToken:async()=>({access_token:accessToken,expires_in:3500})}});
const auth = getAuth();
const config = JSON.parse(readFileSync(new URL('../android/app/src/dev/google-services.json', import.meta.url)));
assert.equal(config.project_info.project_id,projectId);
const apiKey = config.client[0].api_key[0].current_key;
if (process.argv[2] === '--cleanup-only') {
  const headers={Authorization:`Bearer ${accessToken}`,'x-goog-user-project':projectId,'Content-Type':'application/json'};
  const base=`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
  const query=await fetch(`${base}:runQuery`,{method:'POST',headers,body:JSON.stringify({structuredQuery:{from:[{collectionId:'users'}],where:{compositeFilter:{op:'AND',filters:[{fieldFilter:{field:{fieldPath:'__name__'},op:'GREATER_THAN_OR_EQUAL',value:{referenceValue:`projects/${projectId}/databases/(default)/documents/users/foundation-probe-`}}},{fieldFilter:{field:{fieldPath:'__name__'},op:'LESS_THAN',value:{referenceValue:`projects/${projectId}/databases/(default)/documents/users/foundation-probe.`}}}]}}}})});
  assert.ok(query.ok,`Recovery query HTTP ${query.status}`);
  let count=0;
  for(const entry of await query.json()) {
    if(!entry.document) continue;
    const doc=entry.document;
    const testUid=doc.name.split('/').at(-1);
    assert.match(testUid,/^foundation-probe-[0-9a-f-]{36}$/);
    assert.equal(doc.fields.nickname.stringValue,'SentetikKaptan');
    assert.equal(doc.fields.registrationStatus.stringValue,'pendingCompliance');
    const ledger=await fetch(`${base}:runQuery`,{method:'POST',headers,body:JSON.stringify({structuredQuery:{from:[{collectionId:'requestLedger'}],where:{fieldFilter:{field:{fieldPath:'response.result.uid'},op:'EQUAL',value:{stringValue:testUid}}}}})});
    assert.ok(ledger.ok);
    const paths=[`users/${testUid}`,`accountRateLimits/${createHash('sha256').update(`${testUid}|completeRegistration`).digest('hex')}`];
    for(const row of await ledger.json()) if(row.document) paths.push(`requestLedger/${row.document.name.split('/').at(-1)}`);
    for(const path of paths){const r=await fetch(`${base}/${path}`,{method:'DELETE',headers});assert.ok(r.ok||r.status===404,`Recovery delete HTTP ${r.status}`);}
    await auth.deleteUser(testUid).catch(e=>{if(e.code!=='auth/user-not-found')throw e;});
    count++;
  }
  const debug=await fetch(`https://firebaseappcheck.googleapis.com/v1/${appPath}/debugTokens`,{headers});
  assert.ok(debug.ok);
  for(const entry of (await debug.json()).debugTokens??[]) if(entry.displayName==='temporary-foundation-probe') {
    const r=await fetch(`https://firebaseappcheck.googleapis.com/v1/${entry.name}`,{method:'DELETE',headers});assert.ok(r.ok);
  }
  console.log(`Cleaned ${count} strictly identified synthetic probe profiles and temporary debug entries.`);
  process.exit(0);
}
const uid = `foundation-probe-${randomUUID()}`;
const password = `A1${randomBytes(24).toString('hex')}`;
const email = `${uid}@example.invalid`;
const rawId = randomUUID();
const requestId = rawId.slice(0,14)+'7'+rawId.slice(15);
const body = {requestId,schemaVersion:1,payload:{nickname:'SentetikKaptan',grade:3,avatarId:'explorer_basic'}};
const hash = (s)=>createHash('sha256').update(s).digest('hex');
let debugName;
let userCreated=false;
async function jsonRequest(url, body, bearer=accessToken) {
  const result = await fetch(url,{method:'POST',headers:{'Content-Type':'application/json', ...(bearer?{Authorization:`Bearer ${bearer}`,'x-goog-user-project':projectId}:{})},body:JSON.stringify(body)});
  if (!result.ok) throw new Error(`Dev probe request failed: HTTP ${result.status}`);
  return result.json();
}
try {
  await auth.createUser({uid,email,password,emailVerified:true});
  userCreated=true;
  const login=await jsonRequest(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${apiKey}`,{email,password,returnSecureToken:true},null);
  assert.equal(login.localId,uid);
  const callable=`https://europe-west1-${projectId}.cloudfunctions.net/completeRegistration`;
  const noCheck=await fetch(callable,{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${login.idToken}`},body:JSON.stringify({data:body})});
  assert.equal(noCheck.status,401,'Missing App Check must be rejected.');
  const debugToken=randomUUID();
  const debug=await jsonRequest(`https://firebaseappcheck.googleapis.com/v1/${appPath}/debugTokens`,{displayName:'temporary-foundation-probe',token:debugToken});
  debugName=debug.name;
  const checked=await jsonRequest(`https://firebaseappcheck.googleapis.com/v1/${appPath}:exchangeDebugToken?key=${apiKey}`,{debugToken},null);
  assert.ok(checked.token);
  const headers={'Content-Type':'application/json',Authorization:`Bearer ${login.idToken}`,'X-Firebase-AppCheck':checked.token};
  const result=await fetch(callable,{method:'POST',headers,body:JSON.stringify({data:body})});
  assert.equal(result.status,200,'Authenticated dev callable failed.');
  const first=await result.json();
  assert.equal(first.result?.result?.uid,uid);
  assert.equal(first.result?.result?.registrationStatus,'pendingCompliance');
  const replay=await fetch(callable,{method:'POST',headers,body:JSON.stringify({data:body})});
  assert.deepEqual(await replay.json(),first);
  const firestore=`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/users/`;
  const own=await fetch(firestore+uid,{headers:{Authorization:`Bearer ${login.idToken}`}});
  assert.equal(own.status,200);
  const ownBody=await own.json();
  assert.equal(ownBody.fields.nickname.stringValue,body.payload.nickname);
  assert.equal((await fetch(firestore+'not-this-synthetic-uid',{headers:{Authorization:`Bearer ${login.idToken}`}})).status,403);
  assert.equal((await fetch(firestore+uid,{method:'PATCH',headers:{'Content-Type':'application/json',Authorization:`Bearer ${login.idToken}`},body:JSON.stringify({fields:{grade:{integerValue:'5'}}})})).status,403);
  console.log('DEV PASS: Auth; missing App Check denied; registered debug App Check accepted; callable replay; own read; cross-UID and client writes denied.');
  console.log('This verifies dev debug attestation only, not Play Integrity or App Attest.');
} finally {
  const cleanups=[];
  if (debugName) cleanups.push(async()=>{
    const response=await fetch(`https://firebaseappcheck.googleapis.com/v1/${debugName}`,{method:'DELETE',headers:{Authorization:`Bearer ${accessToken}`,'x-goog-user-project':projectId}});
    assert.ok(response.ok,'Temporary debug token cleanup failed.');
  });
  if (userCreated) {
    for (const path of [
      `users/${uid}`,
      `requestLedger/${hash(`${uid}|completeRegistration|${requestId}`)}`,
      `accountRateLimits/${hash(`${uid}|completeRegistration`)}`,
    ]) cleanups.push(async()=>{
      const response=await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${path}`,{method:'DELETE',headers:{Authorization:`Bearer ${accessToken}`,'x-goog-user-project':projectId}});
      assert.ok(response.ok || response.status===404,'Temporary Firestore cleanup failed.');
    });
    cleanups.push(()=>auth.deleteUser(uid));
  }
  const cleaned=await Promise.allSettled(cleanups.map(fn=>fn()));
  assert.ok(cleaned.every(result=>result.status==='fulfilled'),'One or more synthetic data cleanup operations failed.');
  if(userCreated) console.log('Temporary synthetic Auth/profile/ledger/rate data and debug entry cleaned.');
}
