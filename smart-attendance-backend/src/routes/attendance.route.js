const express = require('express');
const router = express.Router();
const auth = require('../middlewares/auth');
const { validateGenerateQr, validateMarkFromQr } = require('../middlewares/attendance.validation');
const { generateQr, markFromQr } = require('../services/attendance.service');
const { handleError } = require('../utils/errors');
const { getAttendanceSessions } = require('../services/moodle.service');
const logger = require('../utils/logger');

// Teacher/admin generates QR token
router.post('/qr', auth, validateGenerateQr, async (req, res) => {
  try {
    // simple teacher guard using TEACHER_SECRET header (dev-friendly)
    const teacherSecret = process.env.TEACHER_SECRET;
    const provided = req.headers['x-teacher-secret'];
    if (teacherSecret && provided !== teacherSecret) return res.status(403).json({ ok: false, code: 'FORBIDDEN', message: 'Invalid teacher secret' });

    const { attendanceId, sessionId, wifiConstraint } = req.validated;
    logger.info('Generate QR requested', {
      userEmail: req.user && req.user.email,
      attendanceId,
      sessionId,
      hasWifiConstraint: Boolean(wifiConstraint),
    });

    const result = await generateQr({ attendanceId, sessionId, wifiConstraint });
    logger.info('Generate QR succeeded', { attendanceId, sessionId });
    res.json(result);
  } catch (err) {
    handleError(err, res);
  }
});

// Student marks attendance using qrToken. Requires auth middleware to set req.user.email in dev mode.
router.post('/mark', auth, validateMarkFromQr, async (req, res) => {
  try {
    const { qrToken, wifiData } = req.validated;

    const userEmail = req.user && req.user.email;
    if (!userEmail) return res.status(401).json({ ok: false, code: 'NO_AUTH', message: 'User email not provided' });

    logger.info('Mark attendance requested', {
      userEmail,
      hasWifiData: Boolean(wifiData),
      hasBssid: Boolean(wifiData && (wifiData.bssid || wifiData.mac || wifiData.macAddress)),
    });

    const takenById = process.env.MOODLE_TAKENBYID; // optional
    const result = await markFromQr({ qrToken, userEmail, takenById, wifiData });
    logger.info('Mark attendance succeeded', {
      userEmail,
      source: result && result.source,
    });
    res.json(result);
  } catch (err) {
    handleError(err, res);
  }
});

// Temporary: return raw sessions from Moodle for an attendance instance
// GET /api/attendance/sessions?attendanceId=XXX
router.get('/sessions', async (req, res) => {
  try {
    const attendanceId = req.query.attendanceId || req.query.attendanceid;
    if (!attendanceId) return res.status(400).json({ ok: false, code: 'MISSING_ATTENDANCE_ID', message: 'attendanceId query parameter is required' });

    const sessions = await getAttendanceSessions(attendanceId);
    // Return raw Moodle response
    res.json(sessions);
  } catch (err) {
    // If it's an ApiError or other known error, prefer consistent handling
    if (err && err.status && err.code) {
      return handleError(err, res);
    }
    // Otherwise return Moodle error wrapper
    return res.status(502).json({ ok: false, code: 'MOODLE_ERROR', message: err.message });
  }
});

module.exports = router;
