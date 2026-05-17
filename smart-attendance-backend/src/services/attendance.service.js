const {
  getUserByEmail,
  getAttendanceSession,
  getAttendanceSessions,
  markAttendance,
} = require('./moodle.service');
const { url: configuredMoodleUrl } = require('../config/moodle.config');
const { ApiError } = require('../utils/errors');
const { signQrToken, verifyQrToken } = require('../utils/jwtQr');
const logger = require('../utils/logger');

function normalizeText(value) {
  if (value === undefined || value === null) return null;
  const normalized = String(value).trim();
  return normalized ? normalized.toLowerCase() : null;
}

function normalizeBssid(value) {
  const text = normalizeText(value);
  if (!text) return null;
  return text.replace(/[^a-f0-9]/g, '');
}

function asPositiveInt(value) {
  const number = Number(value);
  if (!Number.isInteger(number) || number <= 0) return null;
  return number;
}

function isJwtLikeToken(value) {
  const parts = String(value || '').split('.');
  return parts.length === 3 && parts.every(part => part.trim().length > 0);
}

function toCollectionArray(value) {
  if (Array.isArray(value)) return value;
  if (value && typeof value === 'object') return Object.values(value);
  return [];
}

function selectStatusId(statusesInput, { preferPresent = true } = {}) {
  const statuses = toCollectionArray(statusesInput);
  if (statuses.length === 0) {
    throw new ApiError(400, 'PRESENT_STATUS_NOT_FOUND', 'No visible attendance statuses were returned by Moodle');
  }

  let selectedStatus = null;
  if (preferPresent) {
    selectedStatus = statuses.find(status => normalizeText(status.acronym) === 'p');
    if (!selectedStatus) {
      selectedStatus = statuses.find(status => {
        const description = normalizeText(status.description);
        return Boolean(description && description.includes('present'));
      });
    }
  }

  if (!selectedStatus) {
    selectedStatus = statuses
      .slice()
      .sort((left, right) => Number(right.grade || 0) - Number(left.grade || 0))[0];
  }

  const statusId = asPositiveInt(selectedStatus && selectedStatus.id);
  if (!statusId) {
    throw new ApiError(400, 'PRESENT_STATUS_NOT_FOUND', 'Unable to determine which Moodle status should be marked');
  }

  return statusId;
}

function parseMoodleAttendanceUrl(rawValue) {
  if (!rawValue || typeof rawValue !== 'string') return null;

  let parsedUrl;
  try {
    parsedUrl = new URL(rawValue.trim());
  } catch (error) {
    return null;
  }

  const normalizedPath = parsedUrl.pathname.replace(/\/+$/, '').toLowerCase();
  const isAttendancePath =
    normalizedPath === '/mod/attendance/attendance.php' ||
    normalizedPath.endsWith('/mod/attendance/attendance.php');

  if (!isAttendancePath) return null;

  const sessionId = asPositiveInt(parsedUrl.searchParams.get('sessid'));
  if (!sessionId) return null;

  const qrPass = parsedUrl.searchParams.get('qrpass');
  return {
    sessionId,
    qrPass: qrPass && qrPass.trim() ? qrPass.trim() : null,
    host: parsedUrl.host.toLowerCase(),
    hostname: parsedUrl.hostname.toLowerCase(),
    url: parsedUrl.toString(),
  };
}

function getConfiguredMoodleHostname() {
  try {
    return new URL(configuredMoodleUrl).hostname.toLowerCase();
  } catch (error) {
    return null;
  }
}

function validateMoodleQrHost(parsedQr) {
  const expectedHostname = getConfiguredMoodleHostname();
  if (!expectedHostname || !parsedQr || !parsedQr.hostname) return;

  if (parsedQr.hostname !== expectedHostname) {
    logger.warn('Moodle QR host mismatch', {
      expectedHostname,
      observedHostname: parsedQr.hostname,
    });
    throw new ApiError(
      403,
      'QR_LOCATION_MISMATCH',
      'Scanned QR code was generated for a different Moodle/backend host',
    );
  }
}

function buildWifiConstraint(input) {
  if (!input) return null;
  if (typeof input !== 'object' || Array.isArray(input)) {
    throw new ApiError(400, 'INVALID_WIFI_CONSTRAINT', 'wifiConstraint must be an object');
  }

  const bssid = normalizeBssid(input.bssid || input.mac || input.macAddress);
  if (!bssid) throw new ApiError(400, 'INVALID_WIFI_CONSTRAINT', 'wifiConstraint.bssid is required and must be valid');

  return { bssid };
}

function buildObservedWifi(input) {
  if (!input) return null;
  if (typeof input !== 'object' || Array.isArray(input)) {
    throw new ApiError(400, 'INVALID_WIFI_DATA', 'wifiData must be an object');
  }

  return {
    bssid: normalizeBssid(input.bssid || input.mac || input.macAddress),
  };
}

function validateWifiConstraint(expectedConstraint, observedWifi) {
  if (!expectedConstraint) return;
  if (!observedWifi) {
    logger.warn('Wi-Fi validation failed: missing wifiData for constrained QR');
    throw new ApiError(400, 'WIFI_DATA_REQUIRED', 'This QR code requires wifiData for validation');
  }

  if (!expectedConstraint.bssid) return;

  const observedBssid = observedWifi.bssid;
  if (!observedBssid) {
    logger.warn('Wi-Fi validation failed: missing bssid in request');
    throw new ApiError(400, 'WIFI_VALUE_MISSING', 'wifiData.bssid is required');
  }

  if (observedBssid !== expectedConstraint.bssid) {
    logger.warn('Wi-Fi mismatch detected', {
      expectedBssid: expectedConstraint.bssid,
      observedBssid,
    });
    throw new ApiError(403, 'WIFI_MISMATCH', 'wifiData.bssid does not match the QR requirement');
  }

  logger.info('Wi-Fi bssid matched', { bssid: observedBssid });
}

async function getStudentIdByEmail(userEmail) {
  const users = await getUserByEmail(userEmail);
  if (!Array.isArray(users) || users.length === 0) {
    throw new ApiError(404, 'MOODLE_USER_NOT_FOUND', 'User not found in Moodle');
  }

  const studentId = asPositiveInt(users[0].id);
  if (!studentId) {
    throw new ApiError(502, 'MOODLE_ERROR', 'Moodle returned an invalid student id for this email address');
  }

  return studentId;
}

async function getSessionAndPresentStatus(attendanceId, sessionId) {
  const res = await getAttendanceSessions(attendanceId);
  const sessions = toCollectionArray(res);
  if (sessions.length === 0) {
    throw new ApiError(502, 'MOODLE_ERROR', 'Invalid response from Moodle when fetching sessions');
  }

  const session = sessions.find(item => Number(item.id) === Number(sessionId));
  if (!session) throw new ApiError(404, 'SESSION_NOT_FOUND', 'Session not found');

  return {
    statusset: session.statusset,
    presentStatusId: selectStatusId(session.statuses, { preferPresent: true }),
  };
}

function ensureStudentCanUseMoodleSession(session, studentId) {
  if (!session || typeof session !== 'object') {
    throw new ApiError(502, 'MOODLE_ERROR', 'Invalid response from Moodle when fetching the attendance session');
  }

  if (!session.studentscanmark) {
    throw new ApiError(403, 'MOODLE_SELF_MARK_DISABLED', 'This Moodle session is not open for student self-recording');
  }

  if (!session.includeqrcode) {
    throw new ApiError(403, 'MOODLE_QR_DISABLED', 'This Moodle session is not configured to accept QR-based self-recording');
  }

  const sessionUsers = toCollectionArray(session.users);
  const studentInSession = sessionUsers.some(user => Number(user.id) === Number(studentId));
  if (!studentInSession) {
    throw new ApiError(403, 'MOODLE_STUDENT_NOT_IN_SESSION', 'Your Moodle account is not allowed to mark this session');
  }

  const existingLogs = toCollectionArray(session.attendance_log);
  const existingLog = existingLogs.find(log => Number(log.studentid) === Number(studentId));
  if (existingLog) {
    throw new ApiError(409, 'MOODLE_ATTENDANCE_ALREADY_MARKED', 'Attendance is already recorded for this Moodle session');
  }
}

async function generateQr({ attendanceId, sessionId, wifiConstraint }) {
  if (!attendanceId || !sessionId) {
    throw new ApiError(400, 'INVALID_INPUT', 'attendanceId and sessionId are required');
  }

  const payload = {
    attendanceId,
    sessionId,
    nonce: Math.random().toString(36).slice(2),
    wifiConstraint: buildWifiConstraint(wifiConstraint),
  };

  if (payload.wifiConstraint && payload.wifiConstraint.bssid) {
    logger.info('Embedding Wi-Fi constraint into QR', {
      attendanceId,
      sessionId,
      bssid: payload.wifiConstraint.bssid,
    });
  }

  const qrToken = signQrToken(payload);
  return { ok: true, qrToken };
}

async function markFromSignedToken({ qrToken, userEmail, takenById, wifiData }) {
  let decoded;
  try {
    decoded = verifyQrToken(qrToken);
  } catch (error) {
    throw new ApiError(401, 'QR_INVALID', 'QR token is invalid or expired');
  }

  const { attendanceId, sessionId } = decoded;
  if (!attendanceId || !sessionId) {
    throw new ApiError(400, 'INVALID_QR_PAYLOAD', 'QR payload missing attendanceId or sessionId');
  }

  logger.info('JWT attendance QR decoded', {
    userEmail,
    attendanceId,
    sessionId,
    requiresWifiConstraint: Boolean(decoded.wifiConstraint && decoded.wifiConstraint.bssid),
  });

  validateWifiConstraint(decoded.wifiConstraint, buildObservedWifi(wifiData));

  const studentId = await getStudentIdByEmail(userEmail);
  const { statusset, presentStatusId } = await getSessionAndPresentStatus(attendanceId, sessionId);

  await markAttendance({
    sessionid: Number(sessionId),
    studentid: Number(studentId),
    statusid: Number(presentStatusId),
    statusset: String(statusset),
    takenbyid: takenById,
  });

  return { ok: true, source: 'signed_token' };
}

async function markFromMoodleUrl({ qrUrl, userEmail, takenById }) {
  const parsedQr = parseMoodleAttendanceUrl(qrUrl);
  if (!parsedQr) {
    throw new ApiError(400, 'QR_UNSUPPORTED_FORMAT', 'Scanned QR is neither a signed attendance token nor a Moodle attendance QR URL');
  }

  validateMoodleQrHost(parsedQr);

  const studentId = await getStudentIdByEmail(userEmail);
  const session = await getAttendanceSession(parsedQr.sessionId);

  ensureStudentCanUseMoodleSession(session, studentId);

  const statusId = selectStatusId(session.statuses, { preferPresent: true });

  logger.info('Moodle attendance QR parsed', {
    userEmail,
    sessionId: parsedQr.sessionId,
    attendanceId: session.attendanceid,
    hasQrPass: Boolean(parsedQr.qrPass),
    autoAssignStatus: Boolean(session.autoassignstatus),
  });

  await markAttendance({
    sessionid: Number(parsedQr.sessionId),
    studentid: Number(studentId),
    statusid: Number(statusId),
    statusset: String(session.statusset),
    takenbyid: takenById,
  });

  return { ok: true, source: 'moodle_qr' };
}

async function markFromQr({ qrToken, userEmail, takenById, wifiData }) {
  if (isJwtLikeToken(qrToken)) {
    return markFromSignedToken({ qrToken, userEmail, takenById, wifiData });
  }

  const parsedMoodleQr = parseMoodleAttendanceUrl(qrToken);
  if (parsedMoodleQr) {
    return markFromMoodleUrl({ qrUrl: qrToken, userEmail, takenById });
  }

  throw new ApiError(
    400,
    'QR_UNSUPPORTED_FORMAT',
    'Scanned QR is neither a signed attendance token nor a Moodle attendance QR URL',
  );
}

module.exports = {
  getSessionAndPresentStatus,
  generateQr,
  markFromQr,
  parseMoodleAttendanceUrl,
};
