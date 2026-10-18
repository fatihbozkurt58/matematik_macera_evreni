import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

import 'request_envelope.dart';
import 'firebase_dev_bootstrap.dart';

class StudentProfile {
  const StudentProfile({
    required this.uid,
    required this.nickname,
    required this.grade,
    required this.registrationStatus,
    required this.consentComplianceState,
  });

  final String uid;
  final String nickname;
  final int grade;
  final String registrationStatus;
  final String consentComplianceState;

  bool get isBlocked => const {
    'suspended',
    'disabled',
    'deleting',
    'deleted',
  }.contains(registrationStatus);

  bool get canEnterGame =>
      registrationStatus == 'active' && consentComplianceState == 'verified';

  // Browsing the home/catalog does not grant permission to start a game.
  bool get canOpenHome =>
      !isBlocked &&
      consentComplianceState != 'revoked' &&
      const {'active', 'pendingCompliance'}.contains(registrationStatus);

  factory StudentProfile.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) throw StateError('PROFILE_MISSING');
    return StudentProfile.fromData(document.id, data);
  }

  factory StudentProfile.fromData(String uid, Map<String, dynamic> data) {
    final nickname = data['nickname'];
    final grade = data['grade'];
    final status = data['registrationStatus'];
    final compliance = data['consentComplianceState'];
    if (nickname is! String ||
        !RegExp(r'^[a-zA-ZÇĞİÖŞÜçğıöşü][a-zA-ZÇĞİÖŞÜçğıöşü0-9_]{2,19}$')
            .hasMatch(nickname) ||
        grade is! int ||
        grade < 1 ||
        grade > 5 ||
        !const {
          'pendingRegistration',
          'pendingCompliance',
          'active',
          'suspended',
          'disabled',
          'deleting',
          'deleted',
        }.contains(status) ||
        !const {
          'unverified',
          'verified',
          'pending',
          'revoked',
        }.contains(compliance)) {
      throw StateError('PROFILE_INVALID');
    }
    return StudentProfile(
      uid: uid,
      nickname: nickname,
      grade: grade,
      registrationStatus: status as String,
      consentComplianceState: compliance as String,
    );
  }
}

abstract interface class StudentProfileRepository {
  Future<StudentProfile?> load(String uid);
  Stream<StudentProfile?> watch(String uid);
  Future<StudentProfile> complete(String uid, String nickname, int grade);
}

class FirebaseStudentProfileRepository implements StudentProfileRepository {
  FirebaseApp get _app => FirebaseDevBootstrap.app;

  @override
  Stream<StudentProfile?> watch(String uid) =>
      FirebaseFirestore.instanceFor(app: _app)
          .collection('users')
          .doc(uid)
          .snapshots(includeMetadataChanges: true)
          .where((document) => !document.metadata.isFromCache)
          .map(
            (document) =>
                document.exists ? StudentProfile.fromDocument(document) : null,
          );

  @override
  Future<StudentProfile?> load(String uid) async {
    final document = await FirebaseFirestore.instanceFor(app: _app)
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    return document.exists ? StudentProfile.fromDocument(document) : null;
  }

  @override
  Future<StudentProfile> complete(
    String uid,
    String nickname,
    int grade,
  ) async {
    final functions = FirebaseFunctions.instanceFor(
      app: _app,
      region: 'europe-west1',
    );
    final result = await functions
        .httpsCallable('completeRegistration')
        .call(
          requestEnvelope({
            'nickname': nickname,
            'grade': grade,
            'avatarId': 'explorer_basic',
          }, expectedUid: uid),
        );
    final response = result.data is Map ? result.data['result'] : null;
    if (response is! Map || response['uid'] != uid) {
      throw StateError('PROFILE_UID_MISMATCH');
    }
    final profile = await load(uid);
    if (profile == null ||
        profile.nickname != nickname ||
        profile.grade != grade) {
      throw StateError('PROFILE_READBACK_MISMATCH');
    }
    return profile;
  }
}
