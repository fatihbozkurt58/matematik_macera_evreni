import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';

const projectId = process.env.GCLOUD_PROJECT || process.env.FIREBASE_CONFIG_PROJECT_ID;
assert.equal(projectId, 'demo-matematik-evreni', 'Refusing a non-demo Firebase project.');
assert.ok(process.env.FIREBASE_AUTH_EMULATOR_HOST);
assert.ok(process.env.FIRESTORE_EMULATOR_HOST);

const require = createRequire(new URL('../functions/package.json', import.meta.url));
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { createHash } = require('node:crypto');
initializeApp({ projectId });

const authBase = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`;
const firestoreBase = `http://${process.env.FIRESTORE_EMULATOR_HOST}`;
const callable = `http://127.0.0.1:5001/${projectId}/europe-west1/completeRegistration`;
const email = `profile-${Date.now()}@example.invalid`;

async function authRequest(endpoint, body) {
  const response = await fetch(`${authBase}/identitytoolkit.googleapis.com/v1/accounts:${endpoint}?key=fake`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  assert.equal(response.status, 200, `${endpoint}: ${await response.clone().text()}`);
  return response.json();
}

function envelope(payload) {
  const id = randomUUID();
  return { requestId: id.slice(0,14) + '7' + id.slice(15), schemaVersion: 1, payload };
}
async function call(token, data, raw = false, action = 'completeRegistration') {
  const response = await fetch(callable.replace('completeRegistration', action), {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({ data: raw ? data : envelope(data) }),
  });
  return { status: response.status, body: await response.json() };
}

const created = await authRequest('signUp', {
  email,
  password: 'TestOnly12345',
  returnSecureToken: true,
});
const profile = { nickname: 'Matematikci7', grade: 3, avatarId: 'explorer_basic' };
const anonymous = await call(null, profile);
assert.equal(anonymous.body.error?.status, 'UNAUTHENTICATED');
const unverified = await call(created.idToken, profile);
assert.equal(unverified.body.error?.status, 'FAILED_PRECONDITION');

await getAuth().updateUser(created.localId, { emailVerified: true });
const signedIn = await authRequest('signInWithPassword', {
  email,
  password: 'TestOnly12345',
  returnSecureToken: true,
});
const original = envelope(profile);
const first = await call(signedIn.idToken, original, true);
assert.equal(first.status, 200, JSON.stringify(first.body));
assert.equal(first.body.result?.result?.uid, created.localId);
assert.equal(first.body.result?.result?.registrationStatus, 'pendingCompliance');

const repeated = await call(signedIn.idToken, original, true);
assert.equal(repeated.status, 200, JSON.stringify(repeated.body));
assert.deepEqual(repeated.body, first.body, 'Replay must return the original frozen response.');
const reused = await call(signedIn.idToken, { ...original, payload: { ...profile, grade: 4 } }, true);
assert.equal(reused.body.error?.status, 'FAILED_PRECONDITION');
for (const invalid of [profile, {...original, schemaVersion: 2}, {...original, requestId: randomUUID()}, envelope({...profile, uid: 'spoofed'})]) {
  assert.equal((await call(signedIn.idToken, invalid, true)).body.error?.status, 'INVALID_ARGUMENT');
}
const synced = await call(signedIn.idToken, {}, false, 'syncAuthProviders');
assert.deepEqual(synced.body.result?.result?.authProviders, ['password']);
const conflicting = await call(signedIn.idToken, { ...profile, grade: 4 });
assert.equal(conflicting.body.error?.status, 'ALREADY_EXISTS');

const ownRead = await fetch(
  `${firestoreBase}/v1/projects/${projectId}/databases/(default)/documents/users/${created.localId}`,
  { headers: { Authorization: `Bearer ${signedIn.idToken}` } },
);
assert.equal(ownRead.status, 200, await ownRead.clone().text());
const ownDocument = await ownRead.json();
assert.equal(ownDocument.fields.nickname.stringValue, profile.nickname);
assert.equal(ownDocument.fields.grade.integerValue, String(profile.grade));
assert.equal(ownDocument.fields.registrationStatus.stringValue, 'pendingCompliance');
assert.equal(ownDocument.fields.schemaVersion.integerValue, '1');
assert.deepEqual(ownDocument.fields.authProviders.arrayValue.values.map(x => x.stringValue), ['password']);
await getAuth().updateUser(created.localId, { disabled: true });
assert.equal((await call(signedIn.idToken, profile)).body.error?.status, 'PERMISSION_DENIED');
await getAuth().updateUser(created.localId, { disabled: false });
const refreshedLogin=await authRequest('signInWithPassword',{email,password:'TestOnly12345',returnSecureToken:true});
signedIn.idToken=refreshedLogin.idToken;
// Replays do not consume the rate limit; new commands do.
for (let i = 0; i < 19; i++) assert.equal((await call(signedIn.idToken, profile)).status, 200);
assert.equal((await call(signedIn.idToken, profile)).body.error?.status, 'RESOURCE_EXHAUSTED');
console.log('Profile callable: unauthenticated/unverified denied; create/idempotency/conflict and own read passed.');

assert.equal((await call(signedIn.idToken,{...profile,expectedUid:'wrong-uid'})).body.error?.status,'PERMISSION_DENIED');
const updated=await call(signedIn.idToken,{nickname:'YeniKaptan',avatarId:'explorer_basic',expectedProfileRevision:1},false,'updateProfile');
assert.equal(updated.body.result?.result?.profileRevision,2);
assert.equal((await call(signedIn.idToken,{nickname:'EskiKaptan',avatarId:'explorer_basic',expectedProfileRevision:1},false,'updateProfile')).body.error?.status,'ABORTED');
const changed=await call(signedIn.idToken,{grade:4,expectedProfileRevision:2},false,'changeGrade');
assert.equal(changed.body.result?.result?.profileRevision,3);
const userRef=getFirestore().collection('users').doc(created.localId);
await userRef.collection('runtime').doc('activeSession').set({sessionId:'synthetic-active-session'});
assert.equal((await call(signedIn.idToken,{grade:5,expectedProfileRevision:3},false,'changeGrade')).body.error?.status,'FAILED_PRECONDITION');
await userRef.collection('runtime').doc('activeSession').delete();
await userRef.collection('syntheticChild').doc('delete-proof').set({test:true});
assert.equal((await call(signedIn.idToken,{confirmation:'wrong'},false,'requestDeletion')).body.error?.status,'INVALID_ARGUMENT');
const deletion=await call(signedIn.idToken,{confirmation:'DELETE_MY_ACCOUNT'},false,'requestDeletion');
assert.equal(deletion.body.result?.result?.accepted,true);
let deleted=false;
for(let i=0;i<60;i++){
  try{await getAuth().getUser(created.localId);}catch(error){if(error.code==='auth/user-not-found'){deleted=true;break;}throw error;}
  await new Promise(resolve=>setTimeout(resolve,250));
}
assert.ok(deleted,'Deletion worker did not remove synthetic Auth account.');
for(let i=0;i<60;i++){
  const tombstone=await getFirestore().collection('deletionTombstones').doc(createHash('sha256').update(created.localId).digest('hex')).get();
  if(tombstone.exists)break;
  await new Promise(resolve=>setTimeout(resolve,250));
}
assert.equal((await userRef.get()).exists,false);
assert.equal((await userRef.collection('syntheticChild').doc('delete-proof').get()).exists,false);
assert.equal((await getFirestore().collection('requestLedger').where('uid','==',created.localId).get()).size,0);
console.log('Account commands: expected UID, revision conflicts, active-session grade guard and recursive Auth/profile deletion passed.');
