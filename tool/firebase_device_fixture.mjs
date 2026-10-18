import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
assert.equal(process.env.GCLOUD_PROJECT, 'demo-matematik-evreni');
assert.ok(process.env.FIREBASE_AUTH_EMULATOR_HOST);
assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
const require = createRequire(new URL('../functions/package.json', import.meta.url));
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
initializeApp({projectId: 'demo-matematik-evreni'});
for (const uid of ['device-fixture-a', 'device-fixture-b']) {
  await getAuth().createUser({uid, email: `${uid}@example.invalid`, password:'SyntheticOnly1234', emailVerified:true});
}
console.log('Two verified synthetic device fixtures created in demo emulator only.');
