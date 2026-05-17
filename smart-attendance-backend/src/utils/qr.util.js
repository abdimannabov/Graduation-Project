function generateQRPayload(attendanceId, sessionId) {
  return {
    attendance_id: attendanceId,
    session_id: sessionId,
    expires_at: Date.now() + 10 * 60 * 1000,
  };
}

function isExpired(payload) {
  return Date.now() > payload.expires_at;
}

module.exports = { generateQRPayload, isExpired };
