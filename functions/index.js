import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

initializeApp();

const nicknamePattern = /^[a-zA-ZÇĞİÖŞÜçğıöşü][a-zA-ZÇĞİÖŞÜçğıöşü0-9_]{2,19}$/u;
const allowedAvatars = new Set(['explorer_basic']);

export const completeRegistration = onCall(
  {
    region: 'europe-west1',
    enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== 'true',
    maxInstances: 2,
  },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'AUTH_REQUIRED');
    if (request.auth.token.email_verified !== true) {
      throw new HttpsError('failed-precondition', 'EMAIL_NOT_VERIFIED');
    }

    const { nickname, grade, avatarId } = request.data ?? {};
    if (
      typeof nickname !== 'string' ||
      !nicknamePattern.test(nickname) ||
      !Number.isInteger(grade) ||
      grade < 1 ||
      grade > 5 ||
      !allowedAvatars.has(avatarId)
    ) {
      throw new HttpsError('invalid-argument', 'INVALID_PROFILE');
    }

    const uid = request.auth.uid;
    const ref = getFirestore().collection('users').doc(uid);
    return getFirestore().runTransaction(async (transaction) => {
      const existing = await transaction.get(ref);
      if (existing.exists) {
        const profile = existing.data();
        if (
          profile.nickname !== nickname ||
          profile.grade !== grade ||
          profile.avatarId !== avatarId
        ) {
          throw new HttpsError('already-exists', 'PROFILE_ALREADY_EXISTS');
        }
        return { uid, registrationStatus: profile.registrationStatus };
      }

      transaction.create(ref, {
        nickname,
        grade,
        avatarId,
        profileRevision: 1,
        registrationStatus: 'pendingCompliance',
        consentComplianceState: 'unverified',
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return { uid, registrationStatus: 'pendingCompliance' };
    });
  },
);
