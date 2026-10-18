import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

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

  bool get canEnterGame =>
      registrationStatus == 'active' && consentComplianceState == 'verified';

  factory StudentProfile.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) throw StateError('PROFILE_MISSING');
    final nickname = data['nickname'];
    final grade = data['grade'];
    final status = data['registrationStatus'];
    final compliance = data['consentComplianceState'];
    if (nickname is! String ||
        grade is! int ||
        grade < 1 ||
        grade > 5 ||
        status is! String ||
        compliance is! String) {
      throw StateError('PROFILE_INVALID');
    }
    return StudentProfile(
      uid: document.id,
      nickname: nickname,
      grade: grade,
      registrationStatus: status,
      consentComplianceState: compliance,
    );
  }
}

abstract interface class StudentProfileRepository {
  Future<StudentProfile?> load(String uid);
  Future<StudentProfile> complete(String uid, String nickname, int grade);
}

class FirebaseStudentProfileRepository implements StudentProfileRepository {
  FirebaseApp get _app => Firebase.app();

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
    final result = await functions.httpsCallable('completeRegistration').call({
      'nickname': nickname,
      'grade': grade,
      'avatarId': 'explorer_basic',
    });
    final response = result.data;
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
