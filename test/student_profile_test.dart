import 'package:flutter_test/flutter_test.dart';
import 'package:matematik/app/student_profile.dart';
import 'package:matematik/app/request_envelope.dart';

void main() {
  final valid = <String, dynamic>{
    'nickname': 'BilgeKaptan',
    'grade': 3,
    'registrationStatus': 'active',
    'consentComplianceState': 'verified',
  };
  test('Only active verified profile can enter game', () {
    expect(StudentProfile.fromData('uid', valid).canEnterGame, isTrue);
    for (final status in [
      'pendingCompliance',
      'suspended',
      'disabled',
      'deleting',
      'deleted',
    ]) {
      expect(
        StudentProfile.fromData('uid', {
          ...valid,
          'registrationStatus': status,
        }).canEnterGame,
        isFalse,
      );
    }
    expect(
      StudentProfile.fromData('uid', {
        ...valid,
        'consentComplianceState': 'revoked',
      }).canEnterGame,
      isFalse,
    );
  });
  test('Unknown states and malformed profile fail closed', () {
    for (final patch in <Map<String, dynamic>>[
      {'grade': 6},
      {'grade': 1.5},
      {'nickname': 'A'},
      {'registrationStatus': 'unknown'},
      {'consentComplianceState': 'unknown'},
      {'nickname': null},
    ]) {
      expect(
        () => StudentProfile.fromData('uid', {...valid, ...patch}),
        throwsStateError,
      );
    }
  });
  test('Callable envelope has unique UUIDv7 without identity data', () {
    final requests = List.generate(1000, (_) => requestEnvelope({'grade': 3}));
    final ids = requests.map((r) => r['requestId']).toSet();
    expect(ids.length, 1000);
    for (final r in requests) {
      expect(
        r['requestId'],
        matches(
          RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-7[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
          ),
        ),
      );
      expect(r.keys.toSet(), {'requestId', 'schemaVersion', 'payload'});
    }
  });
}
