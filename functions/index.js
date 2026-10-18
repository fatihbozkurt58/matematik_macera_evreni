import { createHash } from 'node:crypto';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';

initializeApp();
const nicknamePattern = /^[a-zA-ZÇĞİÖŞÜçğıöşü][a-zA-ZÇĞİÖŞÜçğıöşü0-9_]{2,19}$/u;
const requestIdPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const options = {
  region: 'europe-west1',
  enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== 'true',
  maxInstances: 2,
};
const digest = (value) => createHash('sha256').update(value).digest('hex');
function fail(code, messageKey, retryable = false) {
  throw new HttpsError(code, messageKey, { code, messageKey, retryable });
}
function exactKeys(value, keys) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    && Object.keys(value).length === keys.length
    && keys.every((key) => Object.hasOwn(value, key));
}

// All writes, the response ledger, and the per-UID rate window commit together.
function accountCommand(action, validate, apply, { recentLogin = false, allowDeleting = false } = {}) {
  return onCall(options, async (request) => {
    if (!request.auth) fail('unauthenticated', 'AUTH_REQUIRED');
    const account = await getAuth().getUser(request.auth.uid).catch(() => {
      fail('unauthenticated', 'SESSION_INVALID');
    });
    if (account.disabled) fail('permission-denied', 'ACCOUNT_DISABLED');
    if (!account.emailVerified) fail('failed-precondition', 'EMAIL_NOT_VERIFIED');
    if (Number(request.auth.token.iat) * 1000 < Date.parse(account.tokensValidAfterTime)) fail('unauthenticated', 'SESSION_INVALID');
    const authTime = Number(request.auth.token.auth_time) * 1000;
    if (recentLogin && (!Number.isFinite(authTime) || Date.now() - authTime > 300000 || authTime > Date.now() + 60000)) {
      fail('failed-precondition', 'RECENT_LOGIN_REQUIRED');
    }
    const envelope = request.data;
    if (!exactKeys(envelope, ['requestId', 'schemaVersion', 'payload'])
        || envelope.schemaVersion !== 1 || !requestIdPattern.test(envelope.requestId)
        || Buffer.byteLength(JSON.stringify(envelope)) > 4096) {
      fail('invalid-argument', 'INVALID_REQUEST');
    }
    if (!envelope.payload || typeof envelope.payload !== 'object' || Array.isArray(envelope.payload)) fail('invalid-argument', 'INVALID_REQUEST');
    const payload = {...envelope.payload};
    const expectedUid = payload.expectedUid;
    delete payload.expectedUid;
    if (expectedUid !== undefined && expectedUid !== account.uid) fail('permission-denied', 'ACCOUNT_CHANGED');
    validate(payload);
    const db = getFirestore();
    const uid = account.uid;
    const userRef = db.collection('users').doc(uid);
    const ledgerRef = db.collection('requestLedger').doc(digest(`${uid}|${action}|${envelope.requestId}`));
    const rateRef = db.collection('accountRateLimits').doc(digest(`${uid}|${action}`));
    const payloadHash = digest(JSON.stringify(envelope.payload, Object.keys(envelope.payload).sort()));
    const now = Date.now();
    return db.runTransaction(async (tx) => {
      const [ledger, rate, user] = await tx.getAll(ledgerRef, rateRef, userRef);
      if (user.exists && ['suspended', 'disabled', ...(allowDeleting ? [] : ['deleting']), 'deleted'].includes(user.data().registrationStatus)) {
        fail('permission-denied', 'ACCOUNT_BLOCKED');
      }
      if (ledger.exists && ledger.data().expiresAt.toMillis() > now) {
        if (ledger.data().payloadHash !== payloadHash) fail('failed-precondition', 'REQUEST_ID_REUSED');
        return ledger.data().response;
      }
      const window = rate.exists && rate.data().windowStart > now - 60000
        ? rate.data() : { windowStart: now, count: 0 };
      if (window.count >= 20) fail('resource-exhausted', 'RATE_LIMITED', true);
      const result = await apply({ tx, user, userRef, account, payload });
      const response = { requestId: envelope.requestId, serverTime: new Date(now).toISOString(), result };
      tx.set(rateRef, { uid, action, windowStart: window.windowStart, count: window.count + 1, expiresAt: Timestamp.fromMillis(now + 86400000) });
      tx.set(ledgerRef, { uid, action, payloadHash, response, expiresAt: Timestamp.fromMillis(now + 48 * 3600000) });
      return response;
    });
  });
}

export const completeRegistration = accountCommand('completeRegistration', (payload) => {
  if (!exactKeys(payload, ['nickname', 'grade', 'avatarId'])
      || typeof payload.nickname !== 'string' || !nicknamePattern.test(payload.nickname)
      || !Number.isInteger(payload.grade) || payload.grade < 1 || payload.grade > 5
      || payload.avatarId !== 'explorer_basic') fail('invalid-argument', 'INVALID_PROFILE');
}, ({ tx, user, userRef, account, payload }) => {
  if (user.exists) {
    const current = user.data();
    if (current.nickname !== payload.nickname || current.grade !== payload.grade || current.avatarId !== payload.avatarId) {
      fail('already-exists', 'PROFILE_ALREADY_EXISTS');
    }
    return { uid: account.uid, registrationStatus: current.registrationStatus, profileRevision: current.profileRevision };
  }
  tx.create(userRef, {
    ...payload,
    schemaVersion: 1,
    authProviders: account.providerData.map((provider) => provider.providerId).sort(),
    profileRevision: 1,
    registrationStatus: 'pendingCompliance',
    consentComplianceState: 'unverified',
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { uid: account.uid, registrationStatus: 'pendingCompliance', profileRevision: 1 };
});

export const syncAuthProviders = accountCommand('syncAuthProviders', (payload) => {
  if (!exactKeys(payload, [])) fail('invalid-argument', 'INVALID_REQUEST');
}, ({ tx, user, userRef, account }) => {
  if (!user.exists) fail('failed-precondition', 'PROFILE_REQUIRED');
  const authProviders = account.providerData.map((provider) => provider.providerId).sort();
  tx.update(userRef, { authProviders, updatedAt: FieldValue.serverTimestamp() });
  return { uid: account.uid, authProviders };
});

function requireProfile(user) {
  if (!user.exists) fail('failed-precondition', 'PROFILE_REQUIRED');
  return user.data();
}
function requireRevision(payload) {
  if (!Number.isSafeInteger(payload.expectedProfileRevision) || payload.expectedProfileRevision < 1) fail('invalid-argument', 'INVALID_REVISION');
}
export const updateProfile = accountCommand('updateProfile', (payload) => {
  if (!exactKeys(payload, ['nickname', 'avatarId', 'expectedProfileRevision'])
      || typeof payload.nickname !== 'string' || !nicknamePattern.test(payload.nickname)
      || payload.avatarId !== 'explorer_basic') fail('invalid-argument', 'INVALID_PROFILE');
  requireRevision(payload);
}, ({ tx, user, userRef, account, payload }) => {
  const current = requireProfile(user);
  if (current.profileRevision !== payload.expectedProfileRevision) fail('aborted', 'PROFILE_REVISION_CHANGED', true);
  const profileRevision = current.profileRevision + 1;
  tx.update(userRef, {nickname: payload.nickname, avatarId: payload.avatarId, profileRevision, updatedAt: FieldValue.serverTimestamp()});
  return {uid: account.uid, nickname: payload.nickname, avatarId: payload.avatarId, profileRevision};
});

export const changeGrade = accountCommand('changeGrade', (payload) => {
  if (!exactKeys(payload, ['grade', 'expectedProfileRevision']) || !Number.isInteger(payload.grade) || payload.grade < 1 || payload.grade > 5) fail('invalid-argument', 'INVALID_GRADE');
  requireRevision(payload);
}, async ({ tx, user, userRef, account, payload }) => {
  const current = requireProfile(user);
  if (current.profileRevision !== payload.expectedProfileRevision) fail('aborted', 'PROFILE_REVISION_CHANGED', true);
  const active = await tx.get(userRef.collection('runtime').doc('activeSession'));
  if (active.exists && active.data().sessionId) fail('failed-precondition', 'SESSION_ACTIVE');
  const profileRevision = current.profileRevision + 1;
  tx.update(userRef, {grade: payload.grade, profileRevision, updatedAt: FieldValue.serverTimestamp()});
  return {uid: account.uid, grade: payload.grade, profileRevision};
}, {recentLogin: true});

export const requestDeletion = accountCommand('requestDeletion', (payload) => {
  if (!exactKeys(payload, ['confirmation']) || payload.confirmation !== 'DELETE_MY_ACCOUNT') fail('invalid-argument', 'DELETION_CONFIRMATION_REQUIRED');
}, ({ tx, user, userRef, account }) => {
  if (!user.exists || user.data().registrationStatus !== 'deleting') {
    tx.set(userRef, {registrationStatus:'deleting', updatedAt:FieldValue.serverTimestamp()}, {merge:true});
    tx.create(getFirestore().collection('deletionRequests').doc(account.uid), {state:'pending',requestedAt:FieldValue.serverTimestamp()});
  }
  return {uid: account.uid, accepted: true};
}, {recentLogin: true, allowDeleting: true});

export const deleteAccountData = onDocumentCreated({document:'deletionRequests/{uid}',region:'europe-west1',retry:true,maxInstances:2}, async (event) => {
  const uid = event.params.uid;
  const db = getFirestore();
  const job = db.collection('deletionRequests').doc(uid);
  try {
    await getAuth().revokeRefreshTokens(uid).catch(error => {if(error.code !== 'auth/user-not-found') throw error;});
    await getAuth().deleteUser(uid).catch(error => {if(error.code !== 'auth/user-not-found') throw error;});
    await db.recursiveDelete(db.collection('users').doc(uid));
    for(const collection of ['requestLedger', 'accountRateLimits']) {
      const documents = await db.collection(collection).where('uid','==',uid).get();
      const writer = db.bulkWriter();
      for(const document of documents.docs) writer.delete(document.ref);
      await writer.close();
    }
    await db.collection('deletionTombstones').doc(digest(uid)).set({completedAt:FieldValue.serverTimestamp(),schemaVersion:1});
    await job.delete();
  } catch (_) {
    await job.set({state:'retrying',lastAttemptAt:FieldValue.serverTimestamp()},{merge:true});
    throw new Error('ACCOUNT_DELETION_RETRY');
  }
});
