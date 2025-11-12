class AttendanceRecord {
  final String userId;
  final String classId;
  final DateTime timestamp;
  final String status;

  AttendanceRecord({
    required this.userId,
    required this.classId,
    required this.timestamp,
    required this.status,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'classId': classId,
      'timestamp': timestamp.toIso8601String(),
      'status': status,
    };
  }
}
