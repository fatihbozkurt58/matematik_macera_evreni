import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'request_envelope.dart';

/// Links only to the authenticated UID; never signs in or merges accounts.
class AccountSecurity {
  AccountSecurity(this.auth, this.functions);
  final FirebaseAuth auth;
  final FirebaseFunctions functions;

  Future<void> linkCredential({
    required AuthCredential reauthentication,
    required AuthCredential newCredential,
  }) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('AUTH_REQUIRED');
    final uid = user.uid;
    final verified = await user.reauthenticateWithCredential(reauthentication);
    if (verified.user?.uid != uid || auth.currentUser?.uid != uid) {
      throw StateError('AUTH_UID_CHANGED');
    }
    await user.linkWithCredential(newCredential);
    if (auth.currentUser?.uid != uid) throw StateError('AUTH_UID_CHANGED');
    await user.getIdToken(true);
    await syncProviders(expectedUid: uid);
  }

  /// Native OAuth uses Firebase's nonce and current-user linking APIs.
  Future<void> linkProvider({
    required AuthCredential reauthentication,
    required AuthProvider provider,
  }) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('AUTH_REQUIRED');
    final uid = user.uid;
    final verified = await user.reauthenticateWithCredential(reauthentication);
    if (verified.user?.uid != uid || auth.currentUser?.uid != uid) {
      throw StateError('AUTH_UID_CHANGED');
    }
    await user.linkWithProvider(provider);
    if (auth.currentUser?.uid != uid) throw StateError('AUTH_UID_CHANGED');
    await user.getIdToken(true);
    await syncProviders(expectedUid: uid);
  }

  /// Retry this when Auth linking succeeded but the server projection failed.
  Future<void> syncProviders({required String expectedUid}) async {
    if (auth.currentUser?.uid != expectedUid) {
      throw StateError('AUTH_UID_CHANGED');
    }
    final response = await functions
        .httpsCallable('syncAuthProviders')
        .call(requestEnvelope({}, expectedUid: expectedUid));
    if (auth.currentUser?.uid != expectedUid ||
        response.data is! Map ||
        response.data['result']?['uid'] != expectedUid) {
      throw StateError('AUTH_UID_CHANGED');
    }
  }

  Future<Map> updateProfile({
    required String nickname,
    required String avatarId,
    required int expectedProfileRevision,
  }) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('AUTH_REQUIRED');
    return _command('updateProfile', uid, {
      'nickname': nickname,
      'avatarId': avatarId,
      'expectedProfileRevision': expectedProfileRevision,
    });
  }

  Future<Map> changeGrade({
    required AuthCredential reauthentication,
    required int grade,
    required int expectedProfileRevision,
  }) async {
    final uid = await _reauthenticate(reauthentication);
    return _command('changeGrade', uid, {
      'grade': grade,
      'expectedProfileRevision': expectedProfileRevision,
    });
  }

  Future<void> deleteAccount({required AuthCredential reauthentication}) async {
    final uid = await _reauthenticate(reauthentication);
    final result = await _command('requestDeletion', uid, {
      'confirmation': 'DELETE_MY_ACCOUNT',
    });
    if (result['accepted'] != true) throw StateError('DELETION_NOT_ACCEPTED');
    if (auth.currentUser?.uid == uid) await auth.signOut();
  }

  Future<String> _reauthenticate(AuthCredential credential) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('AUTH_REQUIRED');
    final verified = await user.reauthenticateWithCredential(credential);
    if (auth.currentUser?.uid != user.uid || verified.user?.uid != user.uid) {
      throw StateError('AUTH_UID_CHANGED');
    }
    await user.getIdToken(true);
    return user.uid;
  }

  Future<Map> _command(
    String name,
    String uid,
    Map<String, Object> payload,
  ) async {
    if (auth.currentUser?.uid != uid) throw StateError('AUTH_UID_CHANGED');
    final response = await functions
        .httpsCallable(name)
        .call(requestEnvelope(payload, expectedUid: uid));
    final result = response.data is Map ? response.data['result'] : null;
    if (auth.currentUser?.uid != uid ||
        result is! Map ||
        result['uid'] != uid) {
      throw StateError('AUTH_UID_CHANGED');
    }
    return result;
  }
}
