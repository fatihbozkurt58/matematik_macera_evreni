import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const projectId = process.env.GCLOUD_PROJECT || process.env.FIREBASE_CONFIG_PROJECT_ID;
assert.equal(projectId, 'demo-matematik-evreni', 'Refusing a non-demo Firebase project.');
assert.ok(process.env.FIREBASE_AUTH_EMULATOR_HOST);
assert.ok(process.env.FIRESTORE_EMULATOR_HOST);

const require = createRequire(new URL('../functions/package.json', import.meta.url));
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
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

async function call(token, data) {
  const response = await fetch(callable, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({ data }),
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
const first = await call(signedIn.idToken, profile);
assert.equal(first.status, 200, JSON.stringify(first.body));
assert.equal(first.body.result?.uid, created.localId);
assert.equal(first.body.result?.registrationStatus, 'pendingCompliance');

const repeated = await call(signedIn.idToken, profile);
assert.equal(repeated.status, 200, JSON.stringify(repeated.body));
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
console.log('Profile callable: unauthenticated/unverified denied; create/idempotency/conflict and own read passed.');
