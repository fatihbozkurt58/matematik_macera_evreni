import assert from 'node:assert/strict';

const projectId = process.env.GCLOUD_PROJECT || process.env.FIREBASE_CONFIG_PROJECT_ID;
assert.equal(projectId, 'demo-matematik-evreni', 'Refusing a non-demo Firebase project.');

for (const name of [
  'FIREBASE_AUTH_EMULATOR_HOST',
  'FIRESTORE_EMULATOR_HOST',
  'FIREBASE_STORAGE_EMULATOR_HOST',
]) {
  assert.ok(process.env[name], `${name} must be set by firebase emulators:exec.`);
}

const auth = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`;
const firestore = `http://${process.env.FIRESTORE_EMULATOR_HOST}`;
const storage = `http://${process.env.FIREBASE_STORAGE_EMULATOR_HOST}`;
const signUp = await fetch(`${auth}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    email: `smoke-${Date.now()}@example.invalid`,
    password: 'TestOnly12345',
    returnSecureToken: true,
  }),
});
if (!signUp.ok) {
  throw new Error(`Auth emulator signup failed: ${signUp.status} ${await signUp.text()}`);
}
const { idToken, localId } = await signUp.json();
assert.ok(idToken && localId, 'Auth emulator did not return a UID and ID token.');
const otherSignUp = await fetch(`${auth}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    email: `other-${Date.now()}@example.invalid`,
    password: 'TestOnly12345',
    returnSecureToken: true,
  }),
});
assert.equal(otherSignUp.status, 200, 'Second synthetic account signup failed.');
const { localId: otherUid } = await otherSignUp.json();
assert.ok(otherUid && otherUid !== localId);

const checks = [
  {
    label: 'Firestore unauthenticated read',
    url: `${firestore}/v1/projects/${projectId}/databases/(default)/documents/users/${localId}`,
  },
  {
    label: 'Firestore own missing profile read',
    url: `${firestore}/v1/projects/${projectId}/databases/(default)/documents/users/${localId}`,
    token: idToken,
    expected: 404,
  },
  {
    label: 'Firestore cross-UID read',
    url: `${firestore}/v1/projects/${projectId}/databases/(default)/documents/users/${otherUid}`,
    token: idToken,
  },
  {
    label: 'Firestore client profile write',
    url: `${firestore}/v1/projects/${projectId}/databases/(default)/documents/users/${localId}`,
    token: idToken,
    method: 'PATCH',
    body: JSON.stringify({ fields: { nickname: { stringValue: 'SahteProfil' } } }),
  },
  {
    label: 'Storage unauthenticated read',
    url: `${storage}/v0/b/${projectId}.firebasestorage.app/o/private%2Fsmoke.txt?alt=media`,
  },
  {
    label: 'Storage authenticated write',
    url: `${storage}/v0/b/${projectId}.firebasestorage.app/o?name=private%2Fsmoke.txt`,
    token: idToken,
    method: 'POST',
    body: 'denied',
  },
];

for (const check of checks) {
  const response = await fetch(check.url, {
    method: check.method || 'GET',
    headers: check.token ? { Authorization: `Bearer ${check.token}` } : {},
    body: check.body,
  });
  const expected = check.expected || 403;
  assert.equal(response.status, expected, `${check.label}: expected ${expected}, got ${response.status}.`);
  console.log(`${check.label}: ${response.status} as expected.`);
}

console.log(`Demo emulator rules passed for UID ${localId}.`);
