import 'dart:math';

/// UUIDv7 uses OS-backed randomness; it contains no UID or device identifier.
Map<String, Object> requestEnvelope(
  Map<String, Object> payload, {
  String? expectedUid,
}) {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  var timestamp = DateTime.now().millisecondsSinceEpoch;
  for (var i = 5; i >= 0; i--) {
    bytes[i] = timestamp & 255;
    timestamp >>= 8;
  }
  bytes[6] = (bytes[6] & 15) | 0x70;
  bytes[8] = (bytes[8] & 63) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final id =
      '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  return {
    'requestId': id,
    'schemaVersion': 1,
    'payload': {
      ...payload,
      if (expectedUid != null) 'expectedUid': expectedUid,
    },
  };
}
